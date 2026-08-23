local s = {}
local u = require('notmuch.util')
local m = require('notmuch.mime')
local thread = require('notmuch.thread')
local v = vim.api

local config = require('notmuch.config')

-- Prompt confirmation for sending an email
local confirm_sendmail = function()
  local choice = v.nvim_call_function('confirm', {
    'Send email?',
    '&Yes\n&No',
    2 -- Default to no
  })

  return choice == 1
end

--- Builds plain text msg from contents into single-part MIME message.
---
--- Used when the composed email has no attachments. Sends as a single part
--- (not MIME `multipart/mixed`) of type `text/plain; charset=UTF-8`.
---
--- @param buf integer: buffer ID of the message compose file
local build_plain_msg = function(buf)
  local main_lines = v.nvim_buf_get_lines(buf, 0, -1, false)

  local attributes, msg = m.get_msg_attributes(main_lines)
  v.nvim_buf_set_lines(buf, 0, -1, false, msg)
  vim.cmd('silent! write!')

  local plain_msg = {}

  for key, value in pairs(attributes) do
    table.insert(plain_msg, key .. ": " .. value)
  end

  table.insert(plain_msg, "MIME-Version: 1.0")
  table.insert(plain_msg, "Content-Type: text/plain; charset=utf-8")
  table.insert(plain_msg, "Content-Transfer-Encoding: 8bit")
  table.insert(plain_msg, "")

  for _, line in ipairs(msg) do
    table.insert(plain_msg, line)
  end

  v.nvim_buf_set_lines(buf, 0, -1, false, plain_msg)
  vim.cmd('silent! write!')
end

--- Builds a multipart MIME message from attachment file paths.
---
--- @param buf integer: buffer ID of the message compose file
--- @param attachment_paths table: list of absolute file path strings
--- @param message_filename string: path to the composed message file
local build_mime_msg_from_attachments = function(buf, attachment_paths, message_filename)
  local main_lines = v.nvim_buf_get_lines(buf, 0, -1, false)

  local attributes, msg = m.get_msg_attributes(main_lines)

  -- Validate attachments BEFORE modifying buffer/file
  local attachments = m.create_mime_attachments(attachment_paths)

  -- Safe to modify buffer now
  v.nvim_buf_set_lines(buf, 0, -1, false, msg)
  vim.cmd('silent! write!')

  local mimes = { {
    file = message_filename,
    type = "text/plain; charset=utf-8",
  } }

  for _, attachment in ipairs(attachments) do
    table.insert(mimes, attachment)
  end

  local mime_table = {
    version = "Mime-Version: 1.0",
    type = "multipart/mixed",
    encoding = "8 bit",
    attributes = attributes,
    mime = mimes,
  }

  local mime_msg = m.make_mime_msg(mime_table)
  v.nvim_buf_set_lines(buf, 0, -1, false, mime_msg)

  vim.cmd('silent! write!')
end

-- Send a completed message via msmtp
s.sendmail = function(filename)
  if not vim.loop.fs_stat(filename) then
    vim.notify('Email file not found: ' .. filename, vim.log.levels.ERROR)
    return false
  end

  local cmd_parts = { 'msmtp', '-t', '--read-envelope-from' }
  if config.options.logfile then
    table.insert(cmd_parts, '--logfile=' .. vim.fn.shellescape(config.options.logfile))
  end
  local msmtp_cmd = table.concat(cmd_parts, ' ') .. ' <' .. vim.fn.shellescape(filename)

  vim.notify('Sending email via msmtp...', vim.log.levels.INFO)

  vim.cmd('botright 15split | terminal')
  local term_buf = v.nvim_get_current_buf()
  local term_job = vim.b.terminal_job_id

  local aug = v.nvim_create_augroup('NotmuchSendmail_' .. term_buf, { clear = true })
  v.nvim_create_autocmd('TermClose', {
    group = aug,
    pattern = '*',
    once = true,
    callback = function(ev)
      if ev.buf ~= term_buf then
        return
      end

      local exit_code = vim.v.event.status or -1

      if exit_code == 0 then
        vim.defer_fn(function() vim.notify('Email sent successfully', vim.log.levels.INFO) end, 500)
      else
        vim.notify('Failed to send email (exit code: ' .. exit_code .. ')', vim.log.levels.ERROR)
      end
    end
  })

  vim.fn.chansend(term_job, msmtp_cmd)
  vim.cmd('startinsert')

  return true
end

--- Sets up the attachment buffer and keymaps common to both compose and reply
--- @param buf number  Main compose/reply buffer
--- @param label string|nil  Human-readable label for the attachment buffer name (e.g. thread id)
local setup_attachments = function(buf, label)
  vim.api.nvim_buf_set_var(buf, 'notmuch_attachments', {})

  local attach_buffer = require('notmuch.attach_buffer')
  local buf_attach = attach_buffer.create_attachment_buffer(buf, label)

  -- :Attach and :AttachRemove commands
  local attach_cmd = require('notmuch.attach_cmd')

  v.nvim_buf_create_user_command(buf, 'Attach', attach_cmd.attach_handler(buf), {
    nargs = 1,
    complete = 'file',
    desc = 'Add file to email attachments'
  })

  v.nvim_buf_create_user_command(buf, 'AttachRemove', attach_cmd.remove_handler(buf), {
    nargs = 1,
    complete = attach_cmd.remove_completion(buf),
    desc = 'Remove attachment by filepath'
  })

  v.nvim_buf_create_user_command(buf, 'AttachList', attach_cmd.list_handler(buf), {
    nargs = 0,
    desc = 'Open attachment buffer'
  })

  -- Keymap for toggling the attachment window:
  -- - If currently in the attachment buffer → close its window and go back
  -- - If the attachment window is already open elsewhere → focus it
  -- - Otherwise → open it in a split below
  -- Registered on both the reply buffer and the attachment buffer.
  local function toggle_attachment_window()
    local ok, current_buf_attach = pcall(v.nvim_buf_get_var, buf, 'notmuch_attach_buf')
    local buf_attach = ok and current_buf_attach or nil

    -- If we are currently inside the attachment buffer, close this window
    if buf_attach and v.nvim_buf_is_valid(buf_attach)
      and v.nvim_get_current_buf() == buf_attach then
      local wins = vim.fn.win_findbuf(buf_attach)
      if #wins > 0 then
        v.nvim_win_close(wins[1], false)
      end
      return
    end

    attach_buffer.show_attachment_window(buf, buf_attach)
  end

  vim.keymap.set('n', config.options.keymaps.attachment_window, toggle_attachment_window,
    { buffer = buf, desc = 'Toggle attachment window' })
  vim.keymap.set('n', config.options.keymaps.attachment_window, toggle_attachment_window,
    { buffer = buf_attach, desc = 'Toggle attachment window' })

  return buf_attach
end

-- Reply to an email message
s.reply = function()
  local id = thread.get_current_message_id()
  if not id then return end

  -- Build a reply filename that embeds both the thread id and message id so
  -- the same draft is reused if the user presses R again on the same thread.
  local thread_meta = vim.b.notmuch_thread or {}
  local thread_id = thread_meta.id or 'unknown'
  local subject = thread_meta.subject or ''
  local label = thread_id .. (subject ~= '' and (' - ' .. subject) or '')
  if #label > 100 then label = label:sub(1, 100) end
  local sanitized_thread = thread_id:gsub('/', '-')
  local sanitized_id = id:gsub('/', '-')
  local reply_filename = '/tmp/reply-' .. sanitized_thread .. '-' .. sanitized_id .. '.eml'

  -- If a draft already exists for this message, reopen it instead of
  -- generating a fresh reply — preserves any edits the user made.
  local draft_exists = u.file_exists(reply_filename)

  -- Check if there is already an open buffer for this draft and switch to it.
  local existing_bufnr = vim.fn.bufnr(reply_filename)
  if existing_bufnr ~= -1 and vim.api.nvim_buf_is_loaded(existing_bufnr) then
    vim.api.nvim_win_set_buf(0, existing_bufnr)
    return
  end

  -- Open (or reopen) the reply file. Using vim.cmd.edit fires BufReadPost /
  -- BufNewFile so plugins like barbecue attach correctly.
  vim.cmd.edit(reply_filename)
  local buf = v.nvim_get_current_buf()

  -- Ensure the buffer is listed so it appears in :ls / buffer pickers
  vim.bo[buf].buflisted = true

  if not draft_exists then
    -- Fresh reply: populate from notmuch reply output
    vim.cmd('silent 0read! notmuch reply id:' .. id)

    -- Strip quoted original message when include_original_response = false.
    -- notmuch reply emits headers, a blank line, then the quoted body starting
    -- with an "On ... wrote:" line followed by "> " prefixed lines.
    -- We keep the headers + blank line and drop everything after.
    if not config.options.include_original_response then
      local lines = v.nvim_buf_get_lines(buf, 0, -1, false)
      local keep_until = #lines  -- default: keep all
      -- Find the first blank line (end of headers) then look for quoted content
      local past_headers = false
      for i, line in ipairs(lines) do
        if not past_headers then
          if line == '' then past_headers = true end
        else
          -- First non-blank line after headers that looks like quoted content
          -- ("On ... wrote:" intro or "> " quoted line) — truncate here.
          if line:match('^On ') or line:match('^>') then
            keep_until = i - 1
            break
          end
        end
      end
      -- Trim trailing blank lines at the cut point, then add one blank + cursor hint
      while keep_until > 1 and lines[keep_until] == '' do
        keep_until = keep_until - 1
      end
      local kept = vim.list_slice(lines, 1, keep_until)
      table.insert(kept, '')  -- blank line after headers for body
      v.nvim_buf_set_lines(buf, 0, -1, false, kept)
      -- Write the trimmed content back to the file so it persists as a draft
      vim.cmd('silent write')
    end
  end

  -- Leave bufhidden at default ("") so the buffer stays in memory and listed
  -- in :ls / pickers when you switch away. It will be wiped explicitly after
  -- sending (see sendmail keymap below).
  -- Place cursor on the first blank line after headers (body start)
  local lines = v.nvim_buf_get_lines(buf, 0, -1, false)
  local body_line = 1
  for i, line in ipairs(lines) do
    if line == '' then body_line = i + 1; break end
  end
  v.nvim_win_set_cursor(0, { math.min(body_line, #lines), 0 })

  setup_attachments(buf, label)

  vim.keymap.set('n', config.options.keymaps.sendmail, function()
    if confirm_sendmail() then
      local attachments = v.nvim_buf_get_var(buf, 'notmuch_attachments')

      if #attachments == 0 then
        build_plain_msg(buf)
      else
        build_mime_msg_from_attachments(buf, attachments, reply_filename)
      end

      s.sendmail(reply_filename)
    end
  end, { buffer = true })
end

-- Compose a new email
s.compose = function(to)
  to = to or ''
  local compose_filename = vim.fn.tempname() .. '-compose.eml'

  local from = config.options.from
  if config.options.from_cmd then
    local out = vim.fn.system(config.options.from_cmd)
    if vim.v.shell_error == 0 and vim.trim(out) ~= '' then
      from = vim.trim(out)
    else
      vim.notify('notmuch.nvim: from_cmd failed, falling back to default From address',
        vim.log.levels.WARN)
    end
  end

  local headers = {
    'From: ' .. from,
    'To: ' .. to,
    'Cc: ',
    'Subject: ',
    '',
    'Message body goes here. Add attachments with "' ..
    config.options.keymaps.attachment_window .. '". Send with "' .. config.options.keymaps.sendmail .. '".',
  }

  vim.cmd.edit(compose_filename)
  local buf = v.nvim_get_current_buf()
  vim.bo[buf].buflisted = true

  v.nvim_buf_set_lines(buf, 0, -1, false, headers)

  setup_attachments(buf)

  vim.keymap.set('n', config.options.keymaps.sendmail, function()
    if confirm_sendmail() then
      local attachments = v.nvim_buf_get_var(buf, 'notmuch_attachments')

      if #attachments == 0 then
        build_plain_msg(buf)
      else
        build_mime_msg_from_attachments(buf, attachments, compose_filename)
      end

      s.sendmail(compose_filename)
    end
  end, { buffer = true })
end

return s
