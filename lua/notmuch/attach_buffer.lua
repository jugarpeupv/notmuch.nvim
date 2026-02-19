---@module 'notmuch.attach_buffer'
---
--- Attachment buffer for compose and reply flows.
--- Works like oil.nvim: each line after the header is a file path.
--- - `dd` deletes an attachment
--- - `p`/`P` pastes file paths (e.g. copied from oil.nvim)
--- - `a` adds via prompt with file completion
--- - `q` closes the window

local AB = {}

local v = vim.api
local u = require('notmuch.util')

--- The separator line between the header and the file list area
local SEPARATOR = '───────────────────'

--- Number of header lines (title + hints + separator)
local HEADER_LINES = 3

--- Builds the fixed header lines
---@return table
local function build_header_lines()
  return {
    '═══ Attachments ═══',
    'Hints: a: Add | dd: Delete | p: Paste | :w Save | q: Close',
    SEPARATOR,
  }
end

---Creates and configures an attachment buffer for a compose/reply buffer.
---The buffer is modifiable below the header so it works like oil.nvim.
---@param main_buf number The compose/reply buffer
---@return number buf_attach The attachment buffer
AB.create_attachment_buffer = function(main_buf)
  -- listed=true, scratch=false so Neovim does NOT force nomodifiable
  local buf_attach = v.nvim_create_buf(true, false)

  v.nvim_buf_set_name(buf_attach, 'attachments:' .. main_buf)

  vim.bo[buf_attach].buftype = 'acwrite'
  vim.bo[buf_attach].bufhidden = 'hide'
  vim.bo[buf_attach].swapfile = false
  vim.bo[buf_attach].modifiable = true

  -- Store reference to main buffer before setting filetype
  v.nvim_buf_set_var(buf_attach, 'notmuch_main_buf', main_buf)

  -- Set filetype (triggers ftplugin) – must come after modifiable = true
  vim.bo[buf_attach].filetype = 'notmuch-attachments'

  -- Ensure modifiable is still true after ftplugin ran
  vim.bo[buf_attach].modifiable = true

  AB.refresh_attachment_display(buf_attach, main_buf)
  AB.setup_keymaps(buf_attach, main_buf)
  AB.setup_sync_autocmd(buf_attach, main_buf)

  -- Store handle on main buffer so it can be retrieved/recreated
  v.nvim_buf_set_var(main_buf, 'notmuch_attach_buf', buf_attach)

  return buf_attach
end

---Refreshes the buffer content from the notmuch_attachments variable
---@param buf_attach number
---@param main_buf number
AB.refresh_attachment_display = function(buf_attach, main_buf)
  if not v.nvim_buf_is_valid(buf_attach) or not v.nvim_buf_is_valid(main_buf) then
    return
  end

  local ok, attachments = pcall(v.nvim_buf_get_var, main_buf, 'notmuch_attachments')
  if not ok then
    attachments = {}
  end

  local lines = build_header_lines()

  if #attachments == 0 then
    table.insert(lines, '')
  else
    for _, path in ipairs(attachments) do
      table.insert(lines, path)
    end
  end

  vim.bo[buf_attach].modifiable = true
  v.nvim_buf_set_lines(buf_attach, 0, -1, false, lines)
  vim.bo[buf_attach].modified = false
end

---Resolves an oil.nvim yanked line to an absolute file path.
---Instead of parsing oil's display format (which varies by user config),
---we use oil's own API: find open oil buffers, match the pasted text
---against their rendered lines, and use oil.get_entry_on_line() +
---oil.get_current_dir() to resolve the real path.
---@param line string The yanked/pasted line from an oil buffer
---@return string|nil resolved absolute path, or nil
local function resolve_oil_line(line)
  local has_oil, oil = pcall(require, 'oil')
  if not has_oil then
    return nil
  end

  local trimmed = vim.trim(line)
  if trimmed == '' then
    return nil
  end

  -- Iterate open oil buffers and compare rendered lines
  for _, bufnr in ipairs(v.nvim_list_bufs()) do
    if v.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'oil' then
      local dir = oil.get_current_dir(bufnr)
      if dir then
        local line_count = v.nvim_buf_line_count(bufnr)
        local buf_lines = v.nvim_buf_get_lines(bufnr, 0, line_count, false)
        for lnum, buf_line in ipairs(buf_lines) do
          if vim.trim(buf_line) == trimmed then
            local entry = oil.get_entry_on_line(bufnr, lnum)
            if entry and entry.type == 'file' then
              -- Ensure trailing slash on dir
              if not dir:match('/$') then
                dir = dir .. '/'
              end
              local full_path = dir .. entry.name
              if vim.loop.fs_stat(full_path) then
                return full_path
              end
            end
          end
        end
      end
    end
  end

  return nil
end

---Transforms the contents of a vim register, converting oil.nvim formatted
---lines into absolute file paths. Lines that are already valid paths are
---kept as-is.
---@param reg_content table register lines
---@return table transformed lines
---@return boolean true if any line was transformed
local function transform_register_for_paste(reg_content)
  local result = {}
  local transformed = false

  for _, line in ipairs(reg_content) do
    local trimmed = vim.trim(line)
    if trimmed == '' then
      table.insert(result, line)
    else
      -- Check if it already looks like a valid absolute path
      local expanded = vim.fn.expand(trimmed)
      expanded = vim.fn.fnamemodify(expanded, ':p')
      if vim.loop.fs_stat(expanded) then
        table.insert(result, expanded)
        if expanded ~= trimmed then
          transformed = true
        end
      else
        -- Try to parse as oil.nvim line
        local resolved = resolve_oil_line(trimmed)
        if resolved then
          table.insert(result, resolved)
          transformed = true
        else
          -- Keep original line; validation on :w will catch it
          table.insert(result, trimmed)
        end
      end
    end
  end

  return result, transformed
end

---Reads file paths from the buffer (lines after the separator)
---@param buf_attach number
---@return table paths
AB.parse_paths_from_buffer = function(buf_attach)
  if not v.nvim_buf_is_valid(buf_attach) then
    return {}
  end

  local all_lines = v.nvim_buf_get_lines(buf_attach, 0, -1, false)
  local paths = {}
  local past_separator = false

  for _, line in ipairs(all_lines) do
    if past_separator then
      local trimmed = vim.trim(line)
      if trimmed ~= '' then
        table.insert(paths, trimmed)
      end
    elseif line == SEPARATOR then
      past_separator = true
    end
  end

  return paths
end

---Syncs buffer content -> notmuch_attachments variable on the main buffer.
---Only runs on :w (BufWriteCmd), not on every TextChanged.
---@param buf_attach number
---@param main_buf number
AB.sync_buffer_to_attachments = function(buf_attach, main_buf)
  if not v.nvim_buf_is_valid(buf_attach) or not v.nvim_buf_is_valid(main_buf) then
    return
  end

  local paths = AB.parse_paths_from_buffer(buf_attach)
  local valid_paths = {}
  local invalid_paths = {}

  for _, path in ipairs(paths) do
    local expanded = vim.fn.expand(path)
    expanded = vim.fn.fnamemodify(expanded, ':p')
    local valid, err = u.validate_attachment_file(expanded)
    if valid then
      table.insert(valid_paths, expanded)
    else
      -- Try resolving as an oil.nvim formatted line before giving up
      local resolved = resolve_oil_line(path)
      if resolved then
        local rv, re = u.validate_attachment_file(resolved)
        if rv then
          table.insert(valid_paths, resolved)
        else
          table.insert(invalid_paths, { path = path, err = re })
        end
      else
        table.insert(invalid_paths, { path = path, err = err })
      end
    end
  end

  if #invalid_paths > 0 then
    local msgs = {}
    for _, inv in ipairs(invalid_paths) do
      table.insert(msgs, '  ' .. inv.path .. ': ' .. (inv.err or 'unknown error'))
    end
    vim.notify('Invalid attachments removed:\n' .. table.concat(msgs, '\n'), vim.log.levels.WARN)
  end

  v.nvim_buf_set_var(main_buf, 'notmuch_attachments', valid_paths)
end

---Sets up TextChanged autocmd for live sync and BufWriteCmd for :w support
---@param buf_attach number
---@param main_buf number
AB.setup_sync_autocmd = function(buf_attach, main_buf)
  local group = v.nvim_create_augroup('NotmuchAttachSync_' .. buf_attach, { clear = true })

  v.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = group,
    buffer = buf_attach,
    callback = function()
      AB.protect_header(buf_attach)
    end,
  })

  -- Intercept :w to sync attachments (like oil.nvim)
  v.nvim_create_autocmd('BufWriteCmd', {
    group = group,
    buffer = buf_attach,
    callback = function()
      AB.sync_buffer_to_attachments(buf_attach, main_buf)

      -- Remove invalid paths from the buffer and refresh display
      AB.refresh_attachment_display(buf_attach, main_buf)

      local ok, attachments = pcall(v.nvim_buf_get_var, main_buf, 'notmuch_attachments')
      local count = ok and #attachments or 0
      vim.notify(
        string.format('Attachments saved: %d file%s', count, count == 1 and '' or 's'),
        vim.log.levels.INFO
      )
    end,
  })
end

---Restores the header if it was modified
---@param buf_attach number
AB.protect_header = function(buf_attach)
  if not v.nvim_buf_is_valid(buf_attach) then
    return
  end

  local current_lines = v.nvim_buf_get_lines(buf_attach, 0, HEADER_LINES, false)
  local expected = build_header_lines()

  local needs_restore = #current_lines < HEADER_LINES
  if not needs_restore then
    for i = 1, HEADER_LINES do
      if current_lines[i] ~= expected[i] then
        needs_restore = true
        break
      end
    end
  end

  if not needs_restore then
    return
  end

  -- Collect file lines (everything that isn't header)
  local all_lines = v.nvim_buf_get_lines(buf_attach, 0, -1, false)
  local file_lines = {}
  local found_sep = false

  for i, line in ipairs(all_lines) do
    if found_sep then
      table.insert(file_lines, line)
    elseif line == SEPARATOR then
      found_sep = true
    elseif i > HEADER_LINES then
      table.insert(file_lines, line)
    end
  end

  if not found_sep and #all_lines > HEADER_LINES then
    for i = HEADER_LINES + 1, #all_lines do
      table.insert(file_lines, all_lines[i])
    end
  end

  local restored = build_header_lines()
  for _, fl in ipairs(file_lines) do
    table.insert(restored, fl)
  end

  -- Temporarily remove autocmd to avoid recursion
  local group_name = 'NotmuchAttachSync_' .. buf_attach
  pcall(v.nvim_del_augroup_by_name, group_name)

  v.nvim_buf_set_lines(buf_attach, 0, -1, false, restored)
  vim.bo[buf_attach].modified = false

  -- Re-create autocmd
  local ok_main, main_buf = pcall(v.nvim_buf_get_var, buf_attach, 'notmuch_main_buf')
  if ok_main then
    AB.setup_sync_autocmd(buf_attach, main_buf)
  end
end

---Sets up keymaps on the attachment buffer
---@param buf_attach number
---@param main_buf number
AB.setup_keymaps = function(buf_attach, main_buf)
  local opts = function(desc)
    return { buffer = buf_attach, desc = desc, nowait = true }
  end

  -- Close window
  vim.keymap.set('n', 'q', function()
    for _, win in ipairs(vim.fn.win_findbuf(buf_attach)) do
      v.nvim_win_close(win, false)
    end
  end, opts('Close attachment window'))

  -- Add attachment via prompt
  vim.keymap.set('n', 'a', function()
    AB.prompt_add_attachment(main_buf, buf_attach)
  end, opts('Add attachment'))

  -- gg goes to first file line, not the header
  vim.keymap.set('n', 'gg', function()
    v.nvim_win_set_cursor(0, { HEADER_LINES + 1, 0 })
  end, opts('Go to first attachment'))

  -- Prevent inserting inside header area
  vim.keymap.set('n', 'i', function()
    local row = v.nvim_win_get_cursor(0)[1]
    if row <= HEADER_LINES then
      v.nvim_win_set_cursor(0, { HEADER_LINES + 1, 0 })
    end
    vim.cmd('startinsert')
  end, opts('Insert'))

  vim.keymap.set('n', 'o', function()
    local row = math.max(v.nvim_win_get_cursor(0)[1], HEADER_LINES)
    v.nvim_buf_set_lines(buf_attach, row, row, false, { '' })
    v.nvim_win_set_cursor(0, { row + 1, 0 })
    vim.cmd('startinsert')
  end, opts('New line below'))

  vim.keymap.set('n', 'O', function()
    local row = v.nvim_win_get_cursor(0)[1]
    if row <= HEADER_LINES then
      row = HEADER_LINES + 1
    end
    v.nvim_buf_set_lines(buf_attach, row - 1, row - 1, false, { '' })
    v.nvim_win_set_cursor(0, { row, 0 })
    vim.cmd('startinsert')
  end, opts('New line above'))

  -- dd: delete line but protect header
  vim.keymap.set('n', 'dd', function()
    local row = v.nvim_win_get_cursor(0)[1]
    if row <= HEADER_LINES then
      return
    end
    vim.cmd('normal! "_dd')
  end, opts('Delete attachment'))

  -- p/P: paste with oil.nvim line conversion, keeping cursor out of header
  vim.keymap.set('n', 'p', function()
    if v.nvim_win_get_cursor(0)[1] < HEADER_LINES then
      v.nvim_win_set_cursor(0, { HEADER_LINES, 0 })
    end
    -- Transform register contents (oil.nvim lines -> absolute paths)
    local reg = vim.v.register ~= '' and vim.v.register or '"'
    local content = vim.fn.getreg(reg, 1, true)
    local transformed, changed = transform_register_for_paste(content)
    if changed then
      vim.fn.setreg(reg, transformed, 'l')
    end
    vim.cmd('normal! p')
  end, opts('Paste'))

  vim.keymap.set('n', 'P', function()
    if v.nvim_win_get_cursor(0)[1] <= HEADER_LINES then
      v.nvim_win_set_cursor(0, { HEADER_LINES + 1, 0 })
    end
    local reg = vim.v.register ~= '' and vim.v.register or '"'
    local content = vim.fn.getreg(reg, 1, true)
    local transformed, changed = transform_register_for_paste(content)
    if changed then
      vim.fn.setreg(reg, transformed, 'l')
    end
    vim.cmd('normal! P')
  end, opts('Paste above'))
end

---Prompts the user to type a file path and adds it
---@param main_buf number
---@param buf_attach number
AB.prompt_add_attachment = function(main_buf, buf_attach)
  vim.ui.input({
    prompt = 'Attachment path: ',
    completion = 'file',
  }, function(path)
    if path and path ~= '' then
      AB.add_attachment(main_buf, buf_attach, path)
    end
  end)
end

---Adds a file path to the attachments and refreshes the buffer
---@param main_buf number
---@param buf_attach number
---@param path string
---@return boolean
AB.add_attachment = function(main_buf, buf_attach, path)
  if not v.nvim_buf_is_valid(main_buf) then
    vim.notify('Main buffer is not valid', vim.log.levels.ERROR)
    return false
  end

  path = vim.fn.expand(path)
  if not path:match('^/') then
    path = vim.fn.fnamemodify(path, ':p')
  end

  local valid, err = u.validate_attachment_file(path)
  if not valid then
    vim.notify('Cannot attach: ' .. err, vim.log.levels.ERROR)
    return false
  end

  local ok, attachments = pcall(v.nvim_buf_get_var, main_buf, 'notmuch_attachments')
  if not ok then
    attachments = {}
  end

  for _, existing in ipairs(attachments) do
    if existing == path then
      vim.notify('File already attached: ' .. path, vim.log.levels.WARN)
      return false
    end
  end

  table.insert(attachments, path)
  v.nvim_buf_set_var(main_buf, 'notmuch_attachments', attachments)

  vim.notify('Attached: ' .. vim.fn.fnamemodify(path, ':t'), vim.log.levels.INFO)

  if buf_attach and v.nvim_buf_is_valid(buf_attach) then
    AB.refresh_attachment_display(buf_attach, main_buf)
  end

  return true
end

---Shows the attachment window (horizontal split below current window).
---Recreates the attachment buffer if it was killed.
---@param main_buf number
---@param buf_attach number|nil
AB.show_attachment_window = function(main_buf, buf_attach)
  -- Recreate buffer if it was killed
  if not buf_attach or not v.nvim_buf_is_valid(buf_attach) then
    buf_attach = AB.create_attachment_buffer(main_buf)
  end

  AB.refresh_attachment_display(buf_attach, main_buf)

  -- Focus existing window if already open
  local wins = vim.fn.win_findbuf(buf_attach)
  if #wins > 0 then
    v.nvim_set_current_win(wins[1])
    return
  end

  v.nvim_open_win(buf_attach, true, {
    split = 'below',
    win = 0,
  })

  -- Ensure modifiable after window opens
  vim.bo[buf_attach].modifiable = true

  v.nvim_win_set_cursor(0, { HEADER_LINES + 1, 0 })
end

return AB
