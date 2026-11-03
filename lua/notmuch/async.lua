--- Asynchronous `notmuch search` support.
---
--- `notmuch search --format=json` is consumed incrementally: JSON objects are
--- parsed in bounded batches as data arrives, and rendered thread lines are
--- appended to the buffer progressively. This keeps Neovim responsive and
--- avoids retaining the complete response in memory.
local a = {}

--- Fits a string into exactly `width` display cells (utf-safe).
--- Embedded newlines (e.g. from folded RFC2822 headers in `subject`/`authors`)
--- are flattened first: `nvim_buf_set_lines` rejects items containing `\n`.
--- Truncation and padding both count display cells (not characters), so wide
--- chars such as emoji or CJK never shift the columns that follow.
local function fit(s, width)
  -- Collapse all whitespace runs (leading blank padding like Outlook's
  -- 43-space subject prefix, tabs, folded newlines) so visible text starts
  -- at column 0 of the field instead of being pushed out of it.
  s = vim.trim((s or ""):gsub("%s+", " "))
  local out, cells = {}, 0
  local n = vim.fn.strchars(s)
  for i = 0, n - 1 do
    local ch = vim.fn.strcharpart(s, i, 1)
    local w = vim.fn.strdisplaywidth(ch)
    if cells + w > width then
      break
    end
    table.insert(out, ch)
    cells = cells + w
  end
  if cells < width then
    table.insert(out, string.rep(" ", width - cells))
  end
  return table.concat(out)
end

--- Nerd Font icons prefixed to thread lines (explicit codepoints, so the file
--- stays readable without a Nerd Font in the editor). Unread threads show a
--- closed envelope (U+F01EE `nf-md-email`), read threads an opened one
--- (U+F01EF `nf-md-email_open`). Swap the codepoints here to use other glyphs.
local ICON_UNREAD = vim.fn.nr2char(0xF01EE) -- nf-md-email: closed envelope (unread)
local ICON_READ = vim.fn.nr2char(0xF01EF) -- nf-md-email_open: opened envelope (read)

--- Reduces a single author string to a display name: trims, strips `<mail>`
--- to the human name, falls back to the mailbox part for bare `<mail@host>`.
local function clean_name(s)
  local from = vim.trim(s or "")
  local name = from:match("^(.-)%s*<")
  if name and vim.trim(name) ~= "" then
    from = vim.trim(name)
  end
  -- A bare "<mail@host>" (no display name) falls back to the mailbox part.
  if from:match("^<.*>$") then
    from = from:gsub("[<>]", ""):match("^[^@]+") or from
  end
  return from
end

--- Formats a single thread object from `notmuch search --format=json` into an
--- aligned display line:
---   ICON DD/MM/YY HH:MM(14)  Subject(40)  From(25)  (tags)  [matched/total]
--- The date uses `os.date`, which renders in the user's local timezone.
--- The icon reflects the `unread` tag; its color comes from the
--- `NotmuchUnreadMail` / `NotmuchReadMail` highlight groups (see syntax file).
local function format_thread(t)
  local tag_list = t.tags or {}
  local unread = false
  for _, tag in ipairs(tag_list) do
    if tag == "unread" then
      unread = true
      break
    end
  end
  local icon = unread and ICON_UNREAD or ICON_READ
  local date = os.date("%d/%m/%y %H:%M", t.timestamp or os.time())
  local subject = fit(t.subject or "", 40)
  -- Show the whole participant list newest-first (notmuch reports `authors`
  -- oldest-first, `|` splits off non-matching authors), cut at 25 cells.
  local authors = t.authors or ""
  local matched = authors:match("^[^|]+") or authors
  local names = {}
  for seg in matched:gmatch("[^,;]+") do
    local name = clean_name(seg)
    if name ~= "" then
      table.insert(names, 1, name)
    end
  end
  local from = fit(table.concat(names, ", "), 25)
  local tags = "(" .. table.concat(t.tags or {}, " ") .. ")"
  local count = string.format("[%d/%d]", t.matched or 0, t.total or 0)
  local line = string.format("%s %s  %s  %s  %s  %s", icon, date, subject, from, tags, count)
  -- Belt and braces: a display line must never contain a newline.
  -- Parentheses truncate gsub's second return (substitution count) so callers
  -- like table.insert(line) don't see a spurious third argument.
  return (line:gsub("[\r\n]", " "))
end

--- Stream `notmuch search --format=json`, decoding records incrementally.
---
--- Unlike a plain `vim.system():wait()`, this never buffers the whole JSON
--- document: complete objects are decoded in bounded batches
--- (`records_per_tick` / `bytes_per_tick`) and handed to `handlers.on_records`
--- as soon as they are available.
---
--- @param query string search terms (see `notmuch-search-terms(7)`)
--- @param handlers table { on_records?: fun(records):boolean?, on_complete?: fun(result) }
---        Returning `false` from `on_records` cancels the stream.
--- @param options? table { sort?: string, records_per_tick?: integer, bytes_per_tick?: integer }
--- @return table request Cancellable handle with a `kill()` method.
function a.stream_notmuch_search(query, handlers, options)
  options = options or {}
  local parser = require("notmuch.search.stream").new()
  local model = require("notmuch.search.model")
  local seen, index = {}, 0

  local request = {
    cancelled = false,
    scheduled = false,
    stdout_done = false,
    exited = nil,
    stderr = "",
    completed = false,
  }

  function request:kill(signal)
    if self.cancelled then
      return
    end
    self.cancelled = true
    if self.process then
      pcall(self.process.kill, self.process, signal or 15)
    end
  end

  local function complete(result)
    if request.completed or request.cancelled then
      return
    end
    request.completed = true
    result.stderr = request.stderr ~= "" and request.stderr or result.stderr
    if handlers.on_complete then
      handlers.on_complete(result)
    end
  end

  local drain
  local function schedule_drain()
    if request.scheduled or request.cancelled or request.completed then
      return
    end
    request.scheduled = true
    vim.schedule(function()
      request.scheduled = false
      drain()
    end)
  end

  drain = function()
    if request.cancelled or request.completed then
      return
    end
    local objects, parse_error =
      parser:drain(options.records_per_tick or 64, options.bytes_per_tick or 128 * 1024)
    local records = {}
    if not parse_error then
      for _, text in ipairs(objects) do
        index = index + 1
        local record, err = model.decode_record(text, index, seen)
        if not record then
          parse_error = err
          break
        end
        records[#records + 1] = record
      end
    end
    if #records > 0 and handlers.on_records then
      if handlers.on_records(records) == false then
        request:kill()
        return
      end
    end
    if parse_error then
      if request.process then
        pcall(request.process.kill, request.process, 15)
      end
      complete({ code = -1, parse_error = parse_error })
      return
    end
    if parser:has_input() then
      schedule_drain()
      return
    end
    if request.stdout_done and request.exited then
      if request.exited.code == 0 then
        local _, finish_error = parser:finish()
        if finish_error then
          complete({ code = -1, signal = request.exited.signal, parse_error = finish_error })
          return
        end
      end
      complete(request.exited)
    end
  end

  local args = { "notmuch", "search", "--format=json" }
  if options.sort then
    args[#args + 1] = "--sort=" .. options.sort
  end
  args[#args + 1] = query

  local ok, process = pcall(vim.system, args, {
    text = true,
    stdout = function(err, data)
      if request.cancelled or request.completed then
        return
      end
      if err then
        request.stderr = (request.stderr .. tostring(err)):sub(1, 8192)
      end
      if data then
        parser:feed(data)
      else
        request.stdout_done = true
      end
      schedule_drain()
    end,
    stderr = function(_, data)
      if data and #request.stderr < 8192 then
        request.stderr = (request.stderr .. data):sub(1, 8192)
      end
    end,
  }, function(result)
    request.exited = result
    schedule_drain()
  end)

  if not ok then
    vim.schedule(function()
      complete({ code = -1, stderr = tostring(process) })
    end)
    return request
  end

  request.process = process
  return request
end

--- Asynchronously runs `notmuch search` and appends rendered thread lines to
--- `buf` as records arrive.
---
--- This keeps the historical interface used by `init.lua`: thread IDs and a
--- full-buffer snapshot are stored in buffer-local variables so tag operations,
--- refreshes, and the `:e` guard keep working.
---
--- @param search string search term to query. see `notmuch-search-terms(7)`
--- @param buf integer buffer id to write the output to
--- @param on_complete fun() callback executed once the process completes
--- @return table request cancellable handle
a.run_notmuch_search = function(search, buf, on_complete)
  local ids = {}

  local function append(records)
    if not vim.api.nvim_buf_is_valid(buf) then
      return false
    end
    local display_lines = {}
    for _, t in ipairs(records) do
      if t.thread then
        table.insert(ids, t.thread)
        table.insert(display_lines, format_thread(t))
      end
    end
    if #display_lines == 0 then
      return true
    end

    -- Paste lines into the tail of `buf`
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, display_lines)
    vim.bo[buf].modifiable = false

    -- Keep IDs in sync after every batch so tag operations work on partial
    -- results. The full `:e` snapshot is refreshed once at completion to
    -- avoid copying the whole buffer on every batch.
    pcall(vim.api.nvim_buf_set_var, buf, "notmuch_thread_ids", ids)
    return true
  end

  local request = a.stream_notmuch_search(search, {
    on_records = append,
    on_complete = function(result)
      if vim.api.nvim_buf_is_valid(buf) then
        pcall(
          vim.api.nvim_buf_set_var,
          buf,
          "notmuch_saved_lines",
          vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        )
      end

      if result.parse_error then
        vim.notify("notmuch search: failed to parse JSON output", vim.log.levels.ERROR)
      elseif result.code ~= 0 then
        vim.notify(
          "notmuch search failed: " .. (result.stderr or ("exit code " .. tostring(result.code))),
          vim.log.levels.ERROR
        )
      end

      -- Keep the completion callback even when the query changed nothing.
      if on_complete then
        on_complete()
      end
    end,
  })

  -- Stop the subprocess as soon as the results buffer is gone (e.g. `q`,
  -- refresh's `bwipeout`, or a replaced query).
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      once = true,
      callback = function()
        request:kill()
      end,
    })
  end

  return request
end

return a
