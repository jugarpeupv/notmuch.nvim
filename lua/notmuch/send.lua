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

  vim.fn.chansend(term_job, msmtp_cmd .. ' ; exit\n')
  vim.cmd('startinsert')

  return true
end

--- Sets up the attachment buffer and keymaps common to both compose and reply
local setup_attachments = function(buf)
  vim.api.nvim_buf_set_var(buf, 'notmuch_attachments', {})

  local attach_buffer = require('notmuch.attach_buffer')
  local buf_attach = attach_buffer.create_attachment_buffer(buf)

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

  -- Keymap for showing attachment window
  vim.keymap.set('n', config.options.keymaps.attachment_window, function()
    local ok, current_buf_attach = pcall(v.nvim_buf_get_var, buf, 'notmuch_attach_buf')
    attach_buffer.show_attachment_window(buf, ok and current_buf_attach or nil)
  end, { buffer = true })

  return buf_attach
end

-- Reply to an email message
s.reply = function()
  local id = thread.get_current_message_id()
  if not id then return end

  local sanitized_id = id:gsub('/', '-')
  local reply_filename = '/tmp/reply-' .. sanitized_id .. '.eml'

  local buf = v.nvim_create_buf(true, false)
  v.nvim_win_set_buf(0, buf)
  vim.cmd.edit(reply_filename)

  if not u.file_exists(reply_filename) then
    vim.cmd('silent 0read! notmuch reply id:' .. id)
  end

  vim.bo.bufhidden = "wipe"
  v.nvim_win_set_cursor(0, { 1, 0 })

  setup_attachments(buf)

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

  local headers = {
    'From: ' .. config.options.from,
    'To: ' .. to,
    'Cc: ',
    'Subject: ',
    '',
    'Message body goes here. Add attachments with "' ..
    config.options.keymaps.attachment_window .. '". Send with "' .. config.options.keymaps.sendmail .. '".',
  }

  local buf = v.nvim_create_buf(true, false)
  v.nvim_win_set_buf(0, buf)
  vim.cmd.edit(compose_filename)

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
