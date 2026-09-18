local nm = {}
local v = vim.api

local config = require('notmuch.config')

-- Setup `notmuch.nvim`
--
-- This function initializes the notmuch.nvim plugin. It defines the entry point
-- command(s) and sets configuration options based on user passed arguments or
-- default values
--
-- @param opts table: Table of options as passed by the user with their config
--                    setup
--
-- @usage
-- -- Example from inside `lazy.nvim` plugin spec configuration
-- {
--   config = function()
--     opts = { ... } -- options go here
--     require('notmuch').setup(opts)
--   end
-- }
nm.setup = function(opts)
  -- Setup configuration defaults and/or user options
  local success = config.setup(opts)

  if not success then
    return
  end

  -- setup user commands
  vim.api.nvim_create_user_command("Notmuch",
    nm.notmuch_hello,
    {
      desc = "notmuch.nvim landing page",
    }
  )
  vim.api.nvim_create_user_command("Inbox", function(arg)
    if #arg.fargs ~= 0 then
      require("notmuch").search_terms("tag:inbox to:" .. arg.args)
    else
      require("notmuch").search_terms("tag:inbox")
    end
  end, {
    desc = "Open inbox",
    nargs = "?",
    complete = require("notmuch.completion").comp_address
  })
  vim.api.nvim_create_user_command("NmSearch", function(arg)
    nm.search_terms(arg.args)
  end, {
    desc = "Notmuch search",
    nargs = "*",
    complete = require("notmuch.completion").comp_search_terms
  })
  vim.api.nvim_create_user_command("ComposeMail", function(arg)
    require("notmuch.send").compose(arg.args)
  end, {
    desc = "Compose mail",
    nargs = "*",
    complete = require("notmuch.completion").comp_address
  })

  -- Ensure thread IDs stay concealed in threads buffer (window-local)
  -- vsplit/split creates a new window where FileType is not re-triggered, so
  -- use BufWinEnter to re-apply for every window showing notmuch-threads.
  -- Also handle CursorMoved to keep it hidden even when cursor is on the
  -- line (concealcursor="" should already hide, but some configs/plugins
  -- may reset it, so re-apply aggressively).
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "CursorMoved", "CursorMovedI", "BufEnter", "FileType", "Syntax" }, {
    group = vim.api.nvim_create_augroup("NotmuchThreadsConceal", { clear = true }),
    callback = function(args)
      local ft = vim.bo[args.buf].filetype
      if ft == "notmuch-threads" or (args.event == "FileType" and args.match == "notmuch-threads") then
        vim.wo.conceallevel = 3
        vim.wo.concealcursor = ""
        -- Also ensure global window options for new windows inherit correctly
        vim.api.nvim_set_option_value("conceallevel", 3, { scope = "local", win = 0 })
        vim.api.nvim_set_option_value("concealcursor", "", { scope = "local", win = 0 })
      end
    end,
  })
end

-- Launch `notmuch.nvim` landing page
--
-- This function launches the main entry point of the plugin into your notmuch
-- database. You are greeted with a list of all the tags in your database,
-- available for querying and/or counting. First line contains help hints.
--
-- If buffer is already open from before, it will simply load it as active
--
-- @usage
-- lua require('notmuch').notmuch_hello()
nm.notmuch_hello = function()
  local bufno = vim.fn.bufnr('Tags')
  if bufno ~= -1 then
    -- Only reuse the buffer if it actually has content.
    -- If a previous load failed silently the buffer may be empty; in that
    -- case wipe it so show_all_tags() does a fresh fetch below.
    local line_count = v.nvim_buf_line_count(bufno)
    local first_line = (line_count > 0) and v.nvim_buf_get_lines(bufno, 0, 1, false)[1] or ""
    if line_count > 1 or first_line ~= "" then
      v.nvim_win_set_buf(0, bufno)
      print("Welcome to Notmuch.nvim! Choose a tag to search it.")
      return
    end
    -- Buffer exists but is empty — wipe it and reload
    v.nvim_buf_delete(bufno, { force = true })
  end
  nm.show_all_tags()
  print("Welcome to Notmuch.nvim! Choose a tag to search it.")
end

-- Conducts a `notmuch search` operation
--
-- This function takes a search term, runs the query against your notmuch
-- database **asynchronously** and returns the list of thread results in a
-- buffer for the user to browse
--
-- @param search string: search terms matching format from
--                       `notmuch-search-terms(7)`
-- @param jumptothreadid string: jump to thread id after search
--
-- @usage
-- lua require('notmuch').search_terms('tag:inbox')
nm.search_terms = function(search, jumptothreadid)
  local num_threads_found = 0
  if search == '' then
    return nil
  elseif string.match(search, '^thread:%S+$') ~= nil then
    nm.show_thread(search)
    return true
  end
  -- Use exact match for buffer name to avoid partial matches
  -- Escape special regex characters in the search term
  local escaped_search = vim.fn.escape(search, '^$.*~[]\\')
  local bufno = vim.fn.bufnr('^' .. escaped_search .. '$')
  if bufno ~= -1 then
    -- Buffer exists, switch to it without refreshing
    -- This preserves cursor position and navigation state
    -- Users can press 'r' to explicitly refresh if needed
    v.nvim_win_set_buf(0, bufno)
    return true
  end
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, search)
  -- Prevent :e from wiping the scratch buffer (not a real file)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  v.nvim_win_set_buf(0, buf)

  local hint_text =
  "Hints: <Enter>: Open thread | <C-v>: Vsplit | <C-s>: Split | q: Close | r: Refresh | %: Sync maildir | a: Archive | A: Archive and Read | +/-/=: Add, remove, toggle tag | o: Sort | dd: Delete"
  v.nvim_buf_set_lines(buf, 0, 2, false, { hint_text, "" })

  -- Async notmuch search to make the UX non blocking
  require('notmuch.async').run_notmuch_search(search, buf, function()
    -- Check if buffer is still valid (might have been deleted during refresh)
    if not v.nvim_buf_is_valid(buf) then
      return
    end
    -- Trim the trailing blank line that the async reader may leave behind
    local line_count = v.nvim_buf_line_count(buf)
    local last_line = v.nvim_buf_get_lines(buf, -2, -1, false)[1] or ''
    if last_line == '' and line_count > 2 then
      vim.bo[buf].modifiable = true
      v.nvim_buf_set_lines(buf, -2, -1, false, {})
      vim.bo[buf].modifiable = false
      line_count = line_count - 1
    end
    -- Completion logic
    if line_count > 1 then num_threads_found = line_count - 1 end
    print('Found ' .. num_threads_found .. ' threads')
    if jumptothreadid and jumptothreadid ~= "" then
      local clean_id = jumptothreadid:match("([0-9a-fA-F]+)") or jumptothreadid
      local ok, ids = pcall(vim.api.nvim_buf_get_var, buf, "notmuch_thread_ids")
      if ok and type(ids) == "table" then
        for idx, tid in ipairs(ids) do
          if tid == clean_id then
            -- Buffer line = idx + 2 (Hints + blank)
            pcall(vim.api.nvim_win_set_cursor, 0, { idx + 2, 0 })
            break
          end
        end
      else
        vim.fn.search(clean_id)
      end
    end
  end)

  -- Set cursor at head of buffer, declare filetype, and disable modifying
  v.nvim_win_set_cursor(0, { 1, 0 })
  vim.bo.filetype = "notmuch-threads"
  vim.bo.modifiable = false
  vim.wo.conceallevel = 3
  vim.wo.concealcursor = ""
end

--- Reverses the threads sorting in `notmuch-threads` buffer
--
-- This function reverses the lines of the `notmuch-threads` buffer which result
-- from the `search_terms()` function. It effectively toggles the sorting of
-- these threads between newest-first and oldest-first.
--
-- We do this instantly instead of running `notmuch search --sort` to save time
-- especially when it comes to large results with thousands of thread.
nm.reverse_sort_threads = function()
  -- Get all lines, disregarding top-level hints line
  local lines = v.nvim_buf_get_lines(0, 0, -1, false)
  local hints = table.remove(lines, 1)

  -- Reverse lines
  local reversed = {}
  for i = #lines, 1, -1 do
    table.insert(reversed, lines[i])
  end

  -- Re-attach hints line
  table.insert(reversed, 1, hints)

  -- Also reverse stored thread IDs to keep mapping consistent
  local buf = vim.api.nvim_get_current_buf()
  local ok, ids = pcall(vim.api.nvim_buf_get_var, buf, "notmuch_thread_ids")
  if ok and type(ids) == "table" then
    local rev_ids = {}
    for i = #ids, 1, -1 do
      table.insert(rev_ids, ids[i])
    end
    pcall(vim.api.nvim_buf_set_var, buf, "notmuch_thread_ids", rev_ids)
  end

  -- Replace lines in buffer
  vim.bo.modifiable = true
  v.nvim_buf_set_lines(0, 0, -1, false, reversed)
  vim.bo.modifiable = false
end

--- Opens a thread in the mail view with all messages in the thread
--
-- This function fetches all the messages in the input thread's ID from the
-- notmuch database and displays them in the mail.vim view.
--
-- @param s string: The string to fetch the threadid from (individual line, or
--                  thread full form)
-- @return true|nil: `true` for successful display, nil for any error
--
-- @usage
-- nm.show_thread("thread:00000000000003aa")
-- nm.show_thread(vim.api.nvim_get_current_line())
-- Helper to get thread ID for a given buffer line (1-indexed), using stored IDs
-- when available (new display without 'thread:' prefix) with fallback to parsing.
local function get_thread_id_at_lnum(buf, lnum)
  if lnum <= 2 then return nil end -- Hints + blank
  local ok, ids = pcall(vim.api.nvim_buf_get_var, buf, "notmuch_thread_ids")
  if ok and type(ids) == "table" and ids[lnum - 2] then
    return ids[lnum - 2]
  end
  local line = vim.fn.getline(lnum)
  if line:find("Hints:") == 1 then return nil end
  -- Fallback for old buffers or direct 'thread:ID' strings
  return string.match(line, "[0-9a-fA-F]+", 7) or string.match(line, "%S+", 8)
end

nm.show_thread = function(s)
  -- Fetch the threadid from the input `s` or from current line
  local threadid = ''
  if s == nil then
    -- fetch from the current line since no input passed
    local line = v.nvim_get_current_line()
    if line:find("Hints:") == 1 then
      -- Skip if selected the Hints line
      print("Cannot open Hints :-)")
      return nil
    end
    local lnum = v.nvim_win_get_cursor(0)[1]
    threadid = get_thread_id_at_lnum(vim.api.nvim_get_current_buf(), lnum) or string.match(line, "[0-9a-z]+", 7) or ""
  else
    -- s may be 'thread:ID', a full line, or just ID
    threadid = string.match(s, "([0-9a-fA-F]+)", 7) or string.match(s, "[0-9a-fA-F]+") or ""
    -- If s is a display line without thread: prefix, fallback to stored IDs
    if threadid == "" or not s:find("thread:") then
      local lnum = v.nvim_win_get_cursor(0)[1]
      local stored = get_thread_id_at_lnum(vim.api.nvim_get_current_buf(), lnum)
      if stored then threadid = stored end
    end
  end
  if threadid == "" or threadid == nil then
    vim.notify("show_thread: could not parse thread ID", vim.log.levels.WARN)
    return nil
  end

  -- Open buffer if already exists and has content, otherwise create new `buf`
  -- Match by prefix since the buffer name may include the subject after the thread ID
  local bufno = vim.fn.bufnr('^thread:' .. threadid)
  if bufno ~= -1 then
    local line_count = v.nvim_buf_line_count(bufno)
    local first_line = (line_count > 0) and v.nvim_buf_get_lines(bufno, 0, 1, false)[1] or ""
    if line_count > 1 or first_line ~= "" then
      -- Buffer exists and has real content, switch to it
      v.nvim_win_set_buf(0, bufno)
      return true
    end
    -- Buffer exists but is empty (e.g. from a failed previous load) — wipe and reload
    v.nvim_buf_delete(bufno, { force = true })
  end
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, "thread:" .. threadid)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  v.nvim_win_set_buf(0, buf)

  -- Get output (JSON parsed) and display lines in buffer
  local lines, metadata = require('notmuch.thread').show_thread(threadid)
  if #lines == 0 then
    vim.notify('show_thread: no content returned for thread:' .. threadid, vim.log.levels.WARN)
    v.nvim_buf_delete(buf, { force = true })
    return nil
  end
  v.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Rename buffer to include the subject for easier buffer switching
  local subject = (metadata.thread or {}).subject or ""
  if subject ~= "" then
    v.nvim_buf_set_name(buf, "thread:" .. threadid .. " " .. subject)
  end

  -- Set up buffer-local variables with thread metadata
  vim.b.notmuch_thread = metadata.thread
  vim.b.notmuch_messages = metadata.messages

  -- Insert hint message at the top of the buffer
  local hint_text =
  "Hints: <Enter>: Toggle fold message | <Tab>: Next message | <S-Tab>: Prev message | q: Close | a: See attachment parts"
  v.nvim_buf_set_lines(buf, 0, 0, false, { hint_text, "" })

  -- Place cursor at head of buffer and prepare display and disable modification
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  v.nvim_win_set_cursor(0, { 1, 0})
  vim.bo.filetype="mail"
  vim.bo.modifiable = false
  vim.wo.conceallevel = 0
  vim.wo.concealcursor = ""

  -- Set up cursor tracking for updating vim.b.notmuch_current
  require('notmuch.thread').setup_cursor_tracking(buf)

  -- Set up gx keymap: pressing gx over a [cid:filename@...] token opens the
  -- image with the system handler (extraction is async, no in-buffer rendering).
  local inline_images = require('notmuch.thread').get_inline_images()
  if #inline_images > 0 then
    vim.keymap.set('n', 'gx', function()
      local line = vim.api.nvim_get_current_line()
      local cursor_col = vim.api.nvim_win_get_cursor(0)[2] + 1  -- 1-based

      -- Find which [cid:FILENAME@...] token the cursor is inside
      local found_filename = nil
      local search_pos = 1
      while true do
        local token_start, token_end, cid_ref = line:find('%[cid:([^%]]+)%]', search_pos)
        if not token_start then break end
        if cursor_col >= token_start and cursor_col <= token_end then
          found_filename = cid_ref:match('^([^@]+)') or cid_ref
          break
        end
        search_pos = token_end + 1
      end

      if not found_filename then
        -- Not on a CID token — fall back to default gx behaviour
        vim.cmd('normal! gx')
        return
      end

      -- Find matching entry in inline_images (prefer match on current line)
      local cur_bufline = vim.api.nvim_win_get_cursor(0)[1]  -- 1-based buffer line
      local entry
      for _, e in ipairs(inline_images) do
        -- entry.line is 1-based in lines[], buffer line = entry.line + HEADER_OFFSET
        local entry_bufline = e.line + 2  -- HEADER_OFFSET = 2
        if entry_bufline == cur_bufline
          and (e.filename == found_filename or e.filename:lower() == found_filename:lower()) then
          entry = e
          break
        end
      end
      -- Fallback: match by filename alone (different message, same filename)
      if not entry then
        for _, e in ipairs(inline_images) do
          if e.filename == found_filename or e.filename:lower() == found_filename:lower() then
            entry = e
            break
          end
        end
      end

      if not entry then
        vim.notify('notmuch: no CID part found for: ' .. found_filename, vim.log.levels.WARN)
        return
      end
      require('notmuch.images').open_cid(entry)
    end, { buffer = buf, desc = 'Open CID inline image with system handler' })
  end
end

--- Helper to ensure conceallevel for notmuch-threads windows
local function ensure_threads_conceal()
  for _, win in ipairs(v.nvim_list_wins()) do
    local buf = v.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == 'notmuch-threads' then
      vim.api.nvim_win_call(win, function()
        vim.wo.conceallevel = 3
        vim.wo.concealcursor = ''
      end)
    end
  end
end

--- Open thread in vertical split (for <C-v> in threads buffer)
nm.show_thread_vsplit = function(s)
  local tid
  if s and s:find("thread:") then
    tid = s:match("thread:([0-9a-fA-F]+)")
  else
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    tid = get_thread_id_at_lnum(vim.api.nvim_get_current_buf(), lnum)
    if not tid and s then tid = s:match("([0-9a-fA-F]+)") end
    if not tid then
      local line = s or v.nvim_get_current_line()
      if line:find("Hints:") == 1 then print("Cannot open Hints :-)") return nil end
      tid = line:match("[0-9a-fA-F]+", 7)
    end
  end
  if not tid or tid == "" then vim.notify("show_thread: could not parse thread ID", vim.log.levels.WARN) return nil end
  vim.cmd('vsplit')
  ensure_threads_conceal()
  return nm.show_thread("thread:" .. tid)
end

--- Open thread in horizontal split (for <C-s> in threads buffer)
nm.show_thread_split = function(s)
  local tid
  if s and s:find("thread:") then
    tid = s:match("thread:([0-9a-fA-F]+)")
  else
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    tid = get_thread_id_at_lnum(vim.api.nvim_get_current_buf(), lnum)
    if not tid and s then tid = s:match("([0-9a-fA-F]+)") end
    if not tid then
      local line = s or v.nvim_get_current_line()
      if line:find("Hints:") == 1 then print("Cannot open Hints :-)") return nil end
      tid = line:match("[0-9a-fA-F]+", 7)
    end
  end
  if not tid or tid == "" then vim.notify("show_thread: could not parse thread ID", vim.log.levels.WARN) return nil end
  vim.cmd('split')
  ensure_threads_conceal()
  return nm.show_thread("thread:" .. tid)
end

-- Counts the number of threads matching the search terms
--
-- This function runs a search query in your `notmuch` database against the
-- argument search terms and returns the number of threads which match
--
-- @param search string: search terms matching format from
--                       `notmuch-search-terms(7)`
--
-- @usage
-- lua require('notmuch').count('tag:inbox') -- > '999'
nm.count = function(search)
  local db = require 'notmuch.cnotmuch' (config.options.notmuch_db_path, 0)
  local q = db.create_query(search)
  local count_threads = q.count_threads()
  db.close()
  return "[" .. search .. "]: " .. count_threads .. " threads"
end

--- Opens the landing/homepage for Notmuch: the `hello` page
--
-- This function opens the main landing page for `notmuch.nvim`. It essentially
-- consists of all the tags in the `notmuch` database for the user to select or
-- count. They can also search from here etc.
--
-- @usage
-- nm.show_all_tags() -- opens the `hello` page
nm.show_all_tags = function()
  -- Wrap the C library calls so a DB error doesn't leave a half-created buffer
  local ok, result = pcall(function()
    local db = require 'notmuch.cnotmuch' (config.options.notmuch_db_path, 0)
    local tags = db.get_all_tags()
    db.close()
    return tags
  end)

  if not ok then
    vim.notify('notmuch.nvim: failed to open database: ' .. tostring(result), vim.log.levels.ERROR)
    return
  end

  local tags = result

  if not tags or #tags == 0 then
    vim.notify('notmuch.nvim: no tags found in database', vim.log.levels.WARN)
    return
  end

  -- Create dedicated buffer. Content is fetched using `db.get_all_tags()`
  local buf = v.nvim_create_buf(true, true)
  v.nvim_buf_set_name(buf, "Tags")
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  v.nvim_win_set_buf(0, buf)
  v.nvim_buf_set_lines(buf, 0, 0, true, tags)

  -- Insert help hints at the top of the buffer
  local hint_text = "Hints: <Enter>: Show threads | q: Close | r: Refresh | %: Refresh maildir | c: Count messages"
  v.nvim_buf_set_lines(buf, 0, 0, false, { hint_text, "" })

  -- Clean up the buffer and set the cursor to the head
  v.nvim_win_set_cursor(0, { 3, 0 })
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  vim.bo.filetype = "notmuch-hello"
  vim.bo.modifiable = false
end

return nm

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
