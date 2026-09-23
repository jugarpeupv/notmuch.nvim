local a = {}

-- Runs `notmuch search` asynchronously
--
-- This function leverages the `vim.loop` library to spawn a subprocess and
-- asynchronously run the `notmuch` search query in the background so it does
-- not block `nvim`s event loop and allow seamless UX while results flow in
--
-- @param search string: search term to query. see `notmuch-search-terms(7)`
-- @param buf int: refers to the buffer id to write the output to
-- @param on_complete func: callback function to execute once process completes
--
-- @usage
-- -- Refer to `init.lua` for example invocation
-- require('notmuch.async').run_notmuch_search('tag:inbox', 0, function()
--   print('Notmuch search process completed.')
-- end)
--- Fits a string into exactly `width` display cells (utf-safe).
--- Embedded newlines (e.g. from folded RFC2822 headers in `subject`/`authors`)
--- are flattened first: `nvim_buf_set_lines` rejects items containing `\n`.
--- Truncation and padding both count display cells (not characters), so wide
--- chars such as emoji or CJK never shift the columns that follow.
local function fit(s, width)
  s = (s or ""):gsub("[\r\n]+", " ")
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

--- Formats a single thread object from `notmuch search --format=json` into an
--- aligned display line:
---   ICON DD/MM/YY HH:MM(14)  Subject(40)  From(25)  (tags)  [matched/total]
--- The date uses `os.date`, which renders in the user's local timezone.
--- The icon reflects the `unread` tag; its color comes from the
--- `NotmuchUnreadMail` / `NotmuchReadMail` highlight groups (see syntax file).
--- Reduces a From/authors string to a display name: trims, strips `<mail>`
--- to the human name, falls back to the mailbox part for bare `<mail@host>`,
--- and fits to 25 display cells.
local function clean_from(s)
  local from = vim.trim(s or "")
  local name = from:match("^(.-)%s*<")
  if name and vim.trim(name) ~= "" then
    from = vim.trim(name)
  end
  -- A bare "<mail@host>" (no display name) falls back to the mailbox part.
  if from:match("^<.*>$") then
    from = from:gsub("[<>]", ""):match("^[^@]+") or from
  end
  return fit(from, 25)
end

--- Finds the newest message's From header in `notmuch show --format=json`
--- output (array of threads, each a tree of [message, replies] nodes).
--- Returns nil when no timestamped message is found.
local function newest_from(show_json)
  local best_ts, best_from = -1, nil
  local function walk(nodes)
    for _, node in ipairs(nodes) do
      if type(node) == "table" then
        local msg, replies = node[1], node[2]
        if type(msg) == "table" and type(msg.timestamp) == "number" and msg.timestamp > best_ts then
          best_ts = msg.timestamp
          best_from = (msg.headers or {}).From
        end
        if type(replies) == "table" then
          walk(replies)
        end
      end
    end
  end
  for _, thread in ipairs(show_json) do
    if type(thread) == "table" then
      walk(thread)
    end
  end
  if best_from and vim.trim(best_from) ~= "" then
    return best_from
  end
  return nil
end

local function format_thread(t, from_override)
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
  -- Without an override, use the last name of the query-matching part of
  -- `authors` (oldest-first, `|` splits off non-matching authors) as a fast
  -- approximation; multi-author threads get refined to the true latest
  -- replier by refine_latest_authors() below.
  local from
  if from_override and from_override ~= "" then
    from = clean_from(from_override)
  else
    local authors = t.authors or ""
    local matched = authors:match("^[^|]+") or authors
    from = clean_from(matched:match("[^,;]+$") or matched)
  end
  local tags = "(" .. table.concat(t.tags or {}, " ") .. ")"
  local count = string.format("[%d/%d]", t.matched or 0, t.total or 0)
  local line = string.format("%s %s  %s  %s  %s  %s", icon, date, subject, from, tags, count)
  -- Belt and braces: a display line must never contain a newline.
  -- Parentheses truncate gsub's second return (substitution count) so callers
  -- like table.insert(line) don't see a spurious third argument.
  return (line:gsub("[\r\n]", " "))
end

--- Refines the From column to the true latest replier for multi-author
--- threads. Single-author threads already show the exact sender, so only
--- threads whose `authors` string holds several names get one cheap
--- `notmuch show --body=false` lookup each (at most MAX_CONCURRENT in
--- flight). Lines are updated in place once answers arrive; failures keep
--- the last-of-authors approximation rendered initially.
local function refine_latest_authors(buf, threads)
  local queue = {}
  for i, t in ipairs(threads) do
    if t.thread and t.authors and t.authors:find("[,|;]") then
      table.insert(queue, { idx = i, tid = t.thread })
    end
  end
  if #queue == 0 then
    return
  end
  local MAX_CONCURRENT = 8
  local active = 0
  local pump
  pump = function()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    while active < MAX_CONCURRENT and #queue > 0 do
      local item = table.remove(queue, 1)
      active = active + 1
      local stdout = vim.loop.new_pipe(false)
      local stderr = vim.loop.new_pipe(false)
      local out = {}
      local function done()
        active = active - 1
        pump()
      end
      local h, err = vim.loop.spawn("notmuch", {
        args = { "show", "--format=json", "--body=false", "--exclude=false", "thread:" .. item.tid },
        stdio = { nil, stdout, stderr },
      }, vim.schedule_wrap(function()
        stdout:close()
        stderr:close()
        if h then
          h:close()
        end
        if vim.api.nvim_buf_is_valid(buf) then
          local ok_json, show_json = pcall(vim.json.decode, table.concat(out))
          if ok_json and type(show_json) == "table" then
            local latest = newest_from(show_json)
            if latest then
              -- The user may have re-sorted since; locate the line by ID.
              local ok_ids, ids = pcall(vim.api.nvim_buf_get_var, buf, "notmuch_thread_ids")
              if ok_ids and type(ids) == "table" then
                for pos, id in ipairs(ids) do
                  if id == item.tid then
                    local fresh = format_thread(threads[item.idx], latest)
                    vim.bo[buf].modifiable = true
                    pcall(vim.api.nvim_buf_set_lines, buf, pos + 1, pos + 2, false, { fresh })
                    vim.bo[buf].modifiable = false
                    break
                  end
                end
              end
            end
          end
        end
        done()
      end))
      if not h then
        stdout:close()
        stderr:close()
        vim.notify("notmuch latest-author lookup failed: " .. tostring(err), vim.log.levels.WARN)
        active = active - 1
        vim.schedule(pump)
      else
        vim.loop.read_start(stdout, function(_, data)
          if data then
            table.insert(out, data)
          end
        end)
        vim.loop.read_start(stderr, vim.schedule_wrap(function(e, _)
          if e then
            vim.notify("ERROR: " .. e)
          end
        end))
      end
    end
  end
  pump()
end

a.run_notmuch_search = function(search, buf, on_complete)
  -- Set up pipes for stdout and stderr to capture command output
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  -- Accumulate raw stdout; `--format=json` yields a single JSON document that
  -- is parsed once the process exits (keeps UX non-blocking via the loop).
  local chunks = {}

  -- Spawn subprocess using vim.loop (deprecated?)
  local handle
  handle = vim.loop.spawn("notmuch", {
    args = {"search", "--format=json", search},
    stdio = {nil, stdout, stderr}
  }, vim.schedule_wrap(function()
    -- Close the pipes and handle
    stdout:close()
    stderr:close()
    handle:close()

    -- Check if buffer is still valid before writing
    -- This prevents errors when buffer is deleted (e.g., during refresh)
    if vim.api.nvim_buf_is_valid(buf) then
      local ok_json, threads = pcall(vim.json.decode, table.concat(chunks))
      if not ok_json or type(threads) ~= "table" then
        vim.notify("notmuch search: failed to parse JSON output", vim.log.levels.ERROR)
      else
        -- Store thread IDs (no 'thread:' prefix is ever displayed, so no
        -- conceal tricks are needed) and format aligned display lines.
        local display_lines = {}
        local ids = {}
        for _, t in ipairs(threads) do
          if t.thread then
            table.insert(ids, t.thread)
            table.insert(display_lines, format_thread(t))
          end
        end
        pcall(vim.api.nvim_buf_set_var, buf, "notmuch_thread_ids", ids)
        -- Save display lines for :e prevention (BufReadCmd will restore)
        pcall(vim.api.nvim_buf_set_var, buf, "notmuch_saved_lines", display_lines)

        -- Paste lines into the tail of `buf`
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, display_lines)
        vim.bo[buf].modifiable = false

        -- Resolve the true latest replier for multi-author threads; lines
        -- refresh in place as answers arrive (failures keep the initial text).
        refine_latest_authors(buf, threads)
      end
    end

    -- Call the completion callback
    on_complete()
  end))

  -- Read data from stdout and accumulate it for JSON parsing on exit
  vim.loop.read_start(stdout, function(_, data)
    if data then
      table.insert(chunks, data)
    end
  end)

  -- Log errors from stderr
  vim.loop.read_start(stderr, vim.schedule_wrap(function(err, _)
    if err then
      vim.notify("ERROR: " .. err)
    end
  end))
end

return a
