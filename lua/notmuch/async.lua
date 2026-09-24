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
