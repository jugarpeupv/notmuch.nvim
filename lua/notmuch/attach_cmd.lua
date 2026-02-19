local a = {}
local u = require('notmuch.util')
local v = vim.api

a.attach_handler = function(buf)
  return function(opts)
    local attachments = v.nvim_buf_get_var(buf, 'notmuch_attachments')

    -- Expand and convert filepath to absolute path
    local filepath = vim.fn.expand(opts.args)
    filepath = vim.fn.fnamemodify(filepath, ':p')

    -- Validate file immediately for user feedback (fail-fast if invalid)
    local valid, err = u.validate_attachment_file(filepath)
    if not valid then
      vim.notify('Cannot attach ' .. filepath .. '\n' .. err, vim.log.levels.ERROR)
      return
    end

    -- Check for duplicates in existing `notmuch_attachments` variable
    for _, path in ipairs(attachments) do
      if path == filepath then
        vim.notify('Already attached: ' .. filepath, vim.log.levels.WARN)
        return
      end
    end

    -- Add to `notmuch_attachments` list and update buffer variable
    table.insert(attachments, filepath)
    v.nvim_buf_set_var(buf, 'notmuch_attachments', attachments)

    -- Report success
    vim.notify(string.format('Attached: %s (%d total)', filepath, #attachments), vim.log.levels.INFO)
    
    -- Refresh attachment buffer if it exists
    local buf_attach_name = 'attachments:' .. buf
    local buf_attach = vim.fn.bufnr('^' .. vim.fn.escape(buf_attach_name, '^$.*[]~') .. '$')
    if buf_attach ~= -1 then
      require('notmuch.attach_buffer').refresh_attachment_display(buf_attach, buf)
    end
  end
end

a.remove_handler = function(buf)
  return function(opts)
    local attachments = v.nvim_buf_get_var(buf, 'notmuch_attachments')
    local filepath = vim.fn.expand(opts.args)

    -- Find and remove the file from attachments
    local found_index = nil
    for i, path in ipairs(attachments) do
      if path == filepath then
        found_index = i
      end
    end

    -- Show error if not found
    if not found_index then
      vim.notify('File not in attachments: ' .. filepath, vim.log.levels.ERROR)
      return
    end

    -- Remove from `attachments` and update back to buffer
    table.remove(attachments, found_index)
    v.nvim_buf_set_var(buf, 'notmuch_attachments', attachments)

    -- Report success
    vim.notify(string.format('Removed: %s (%d remaining)', filepath, #attachments), vim.log.levels.INFO)
    
    -- Refresh attachment buffer if it exists
    local buf_attach_name = 'attachments:' .. buf
    local buf_attach = vim.fn.bufnr('^' .. vim.fn.escape(buf_attach_name, '^$.*[]~') .. '$')
    if buf_attach ~= -1 then
      require('notmuch.attach_buffer').refresh_attachment_display(buf_attach, buf)
    end
  end
end

a.remove_completion = function(buf)
  return function()
    return v.nvim_buf_get_var(buf, 'notmuch_attachments')
  end
end

a.list_handler = function(buf)
  return function()
    local ok, buf_attach = pcall(vim.api.nvim_buf_get_var, buf, 'notmuch_attach_buf')
    require('notmuch.attach_buffer').show_attachment_window(buf, ok and buf_attach or nil)
  end
end

return a
