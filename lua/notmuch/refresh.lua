local r = {}
local v = vim.api
local nm = require('notmuch')

-- Refreshes the search results buffer
--
-- This function refreshes the buffer showing the results of a search (list of
-- threads) by deleting the original buffer and re-invokes the `search_terms()`
-- function.
--
-- @usage
-- -- Normally invoked by pressing `r` in the search results buffer
-- lua require('notmuch.refresh').refresh_search_buffer()
r.refresh_search_buffer = function()
  local line = v.nvim_get_current_line()
  local threadid = string.match(line, "%S+", 8)
  local search = string.match(v.nvim_buf_get_name(0), '%a+:%C+')
  v.nvim_command('bwipeout')
  nm.search_terms(search, threadid)
  vim.fn.search(threadid)
end

-- Refreshes the thread view buffer
--
-- This function refreshes the buffer containing a thread view with all its
-- messages inside by re-fetching the thread data and repopulating the current
-- buffer in-place (without wiping and recreating it).
--
-- @usage
-- -- Normally invoked by pressing `r` in the thread view buffer
-- lua require('notmuch.refresh').refresh_thread_buffer()
r.refresh_thread_buffer = function()
  local bufname = v.nvim_buf_get_name(0)
  -- Extract just the thread ID (hex chars after "thread:")
  local threadid = string.match(bufname, 'thread:([0-9a-z]+)')
  if not threadid then
    return
  end

  local buf = v.nvim_get_current_buf()

  -- Re-fetch thread data
  local lines, metadata = require('notmuch.thread').show_thread(threadid)

  if #lines == 0 then
    vim.notify('Thread refresh: no content returned for ' .. threadid, vim.log.levels.WARN)
    return
  end

  -- Repopulate buffer in-place
  vim.bo.modifiable = true
  v.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Update buffer name (subject may have changed), only if different
  local subject = (metadata.thread or {}).subject or ""
  local new_name = "thread:" .. threadid
  if subject ~= "" then
    new_name = new_name .. " " .. subject
  end
  if v.nvim_buf_get_name(buf) ~= new_name then
    pcall(v.nvim_buf_set_name, buf, new_name)
  end

  -- Refresh buffer-local metadata
  vim.b.notmuch_thread = metadata.thread
  vim.b.notmuch_messages = metadata.messages

  -- Re-insert hint line at top
  local hint_text =
    "Hints: <Enter>: Toggle fold message | <Tab>: Next message | <S-Tab>: Prev message | q: Close | a: See attachment parts"
  v.nvim_buf_set_lines(buf, 0, 0, false, { hint_text, "" })

  -- Clean up trailing blank line, reset cursor, lock buffer
  v.nvim_buf_set_lines(buf, -2, -1, true, {})
  v.nvim_win_set_cursor(0, { 1, 0 })
  vim.bo.modifiable = false

  print("Thread refreshed")
end

-- Refreshes the notmuch landing page buffer
--
-- This function refreshes the `notmuch-hello` landing page buffer by deleting
-- the original buffer (wipeout to flush it from memory) and invokes the
-- `show_all_tags()` function again. This is useful when you know changes have
-- been made to the buffer contents and want to reflect it accordingly
--
-- @usage
-- -- Normally invoked by pressing `r` in the Tags buffer
-- lua require('notmuch.refresh').refresh_hello_buffer()
r.refresh_hello_buffer = function()
  v.nvim_command('bwipeout')
  nm.show_all_tags()
end

return r
