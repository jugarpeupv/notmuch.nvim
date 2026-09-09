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
a.run_notmuch_search = function(search, buf, on_complete)
  -- Set up pipes for stdout and stderr to capture command output
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  -- Spawn subprocess using vim.loop (deprecated?)
  local handle
  handle = vim.loop.spawn("notmuch", {
    args = {"search", search},
    stdio = {nil, stdout, stderr}
  }, vim.schedule_wrap(function()
    -- Close the pipes and handle
    stdout:close()
    stderr:close()
    handle:close()

    -- Call the completion callback
    on_complete()
  end))

  -- Helper variable for maintaining incomplete lines between reads
  local partial_data = ""

  -- Read data from stdout and write it to the buffer
  vim.loop.read_start(stdout, vim.schedule_wrap(function(_, data)
    if data then
      -- Combine earlier incomplete chunk with newest read
      partial_data = partial_data .. data
      local lines = vim.split(partial_data, '\n')
      -- collect incomplete line at the tail of lines
      partial_data = table.remove(lines)

      -- Check if buffer is still valid before writing
      -- This prevents errors when buffer is deleted (e.g., during refresh)
      if not vim.api.nvim_buf_is_valid(buf) then
        handle:kill()
        return
      end

      -- Store thread IDs and hide 'thread:' prefix (never visible, even on
      -- cursor line - fixes concealcursor=n showing it). Remove prefix entirely
      -- so date starts at column 0 (no indent) and keep syntax working.
      local display_lines = {}
      local ok, ids = pcall(vim.api.nvim_buf_get_var, buf, "notmuch_thread_ids")
      if not ok or type(ids) ~= "table" then
        ids = {}
        pcall(vim.api.nvim_buf_set_var, buf, "notmuch_thread_ids", ids)
      end
      for _, line in ipairs(lines) do
        local tid = line:match("^thread:([0-9a-fA-F]+)")
        if tid then
          table.insert(ids, tid)
          -- Remove 'thread:<id>' and following spaces (no indent, date at col 0)
          local prefix = line:match("^thread:[0-9a-fA-F]+%s*")
          if prefix then
            line = line:sub(#prefix + 1)
          else
            line = line:gsub("^thread:[0-9a-fA-F]+", "")
          end
        end
        table.insert(display_lines, line)
      end
      -- Ensure buffer var is updated (table is reference, but set again for safety)
      pcall(vim.api.nvim_buf_set_var, buf, "notmuch_thread_ids", ids)

      -- Paste lines into the tail of `buf`
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, display_lines)
      vim.bo[buf].modifiable = false
    end
  end))

  -- Log errors from stderr
  vim.loop.read_start(stderr, vim.schedule_wrap(function(err, _)
    if err then
      vim.notify("ERROR: " .. err)
    end
  end))
end

return a
