local s = {}
local u = require('notmuch.util')
local m = require('notmuch.mime')
local thread = require('notmuch.thread')
local v = vim.api

local config = require('notmuch.config')

--- Detects which of the user's identities received a specific message.
--- Inspects the message's recipient headers (To / Cc) against the message's
--- folder path and tags (e.g. gmail vs izertis), then against user.name,
--- and finally falls back to the single recipient in To if present.
--- Returns nil if no specific recipient identity can be determined.
---@param msg_id string
---@return string|nil
local detect_received_identity = function(msg_id)
  if not msg_id or msg_id == '' then
    return nil
  end
  local out = vim.fn.system({ 'notmuch', 'show', '--format=json', '--body=false', 'id:' .. msg_id })
  local ok, data = pcall(vim.json.decode, out)
  if not ok or not data or not data[1] or not data[1][1] or not data[1][1][1] then
    return nil
  end
  local msg = data[1][1][1]
  local headers = msg.headers or {}
  local to_hdr = headers.To or ''
  local cc_hdr = headers.Cc or ''

  local function parse_addrs(str)
    local list = {}
    if not str or str == '' then
      return list
    end
    for _, p in ipairs(vim.split(str, ',', { plain = true })) do
      local trimmed = vim.trim(p)
      if trimmed ~= '' then
        local name, addr = trimmed:match('^(.-)%s*<([^>]+)>%s*$')
        if addr then
          table.insert(list, { full = trimmed, name = vim.trim(name), email = addr:lower() })
        else
          local bare = trimmed:match('%S+@%S+')
          if bare then
            table.insert(list, { full = trimmed, name = '', email = bare:lower() })
          end
        end
      end
    end
    return list
  end

  local all_recipients = parse_addrs(to_hdr)
  for _, r in ipairs(parse_addrs(cc_hdr)) do
    table.insert(all_recipients, r)
  end
  if #all_recipients == 0 then
    return nil
  end

  -- Strategy 1: Check maildir path or tags to identify account domain
  local filenames = msg.filename or {}
  local tags = msg.tags or {}
  local is_gmail = false
  local is_izertis = false
  for _, f in ipairs(filenames) do
    local fl = f:lower()
    if fl:find('gmail') then is_gmail = true end
    if fl:find('izertis') then is_izertis = true end
  end
  for _, t in ipairs(tags) do
    local tl = t:lower()
    if tl:find('gmail') then is_gmail = true end
    if tl:find('izertis') then is_izertis = true end
  end

  if is_gmail then
    for _, r in ipairs(all_recipients) do
      if r.email:find('gmail%.com') then
        return r.full
      end
    end
  end
  if is_izertis then
    for _, r in ipairs(all_recipients) do
      if r.email:find('izertis%.com') then
        return r.full
      end
    end
  end

  -- Strategy 2: If single recipient in To, that recipient is who received it
  local to_recipients = parse_addrs(to_hdr)
  if #to_recipients == 1 then
    return to_recipients[1].full
  end

  -- Strategy 3: Match against notmuch user.name
  local user_name = vim.fn.trim(vim.fn.system('notmuch config get user.name')):lower()
  if user_name ~= '' then
    for _, r in ipairs(all_recipients) do
      if r.name:lower():find(user_name, 1, true) then
        return r.full
      end
    end
  end

  -- Fallback: first recipient in To
  if #to_recipients > 0 then
    return to_recipients[1].full
  end

  return nil
end

--- Resolves the From address for outgoing mail.
--- For replies, pass `msg_id` so the address where the user received the email
--- takes precedence over global config. `from_cmd` and `config.options.from`
--- act as fallback (or as primary for new compose messages).
---@param msg_id string|nil
---@return string
local resolve_from = function(msg_id)
  if msg_id then
    local received = detect_received_identity(msg_id)
    if received and received ~= '' then
      return received
    end
  end
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
  return from
end

--- Decodes RFC 2047 encoded-word strings (e.g. "=?iso-8859-1?Q?Generaci=F3n?="
--- or "=?utf-8?B?...?=") into readable UTF-8 text so compose/reply headers
--- (Subject, To, Cc, etc.) are human-editable.
---
--- Supports:
--- - Q (quoted-printable) and B (base64) encodings (case-insensitive)
--- - charsets: utf-8, ascii, iso-8859-1/latin1, windows-1252/cp1252
--- - discards linear whitespace between adjacent encoded words (per RFC 2047 §6.2)
--- - leaves unrecognized charsets/encodings intact as fallback
---@param s string|nil
---@return string|nil
local decode_rfc2047 = function(s)
  if not s or not s:find('=?', 1, true) then
    return s
  end
  local base64 = require('notmuch.base64')

  local function decode_word(charset, enc, text)
    charset = charset:lower()
    enc = enc:upper()
    local bytes = ''
    if enc == 'B' then
      local ok, decoded = pcall(base64.decode, text)
      if ok then
        bytes = decoded
      else
        return nil
      end
    elseif enc == 'Q' then
      -- RFC 2047 §4.2: '_' represents space (0x20), =XX represents hex byte
      bytes = text:gsub('_', ' '):gsub('=([0-9A-Fa-f][0-9A-Fa-f])', function(hex)
        return string.char(tonumber(hex, 16))
      end)
    else
      return nil
    end

    if charset == 'utf-8' or charset == 'us-ascii' or charset == 'ascii' then
      -- Normalize any encoded newlines/carriage returns (e.g. =0A) to spaces
      return (bytes:gsub('[\r\n]+', ' '))
    elseif charset == 'iso-8859-1' or charset == 'latin1'
        or charset == 'windows-1252' or charset == 'cp1252' then
      -- Convert ISO-8859-1 single-byte high codepoints (0x80..0xFF) to UTF-8
      local out = {}
      for i = 1, #bytes do
        local b = bytes:byte(i)
        if b < 0x80 then
          table.insert(out, string.char(b))
        else
          local c1 = 0xC0 + math.floor(b / 64)
          local c2 = 0x80 + (b % 64)
          table.insert(out, string.char(c1, c2))
        end
      end
      return (table.concat(out):gsub('[\r\n]+', ' '))
    else
      return (bytes:gsub('[\r\n]+', ' '))
    end
  end

  -- Discard linear whitespace between adjacent encoded words (RFC 2047 §6.2)
  s = s:gsub('(=%?[^?]+%?[BbQq]%?[^?]+%?=)%s+(=%?[^?]+%?[BbQq]%?[^?]+%?=)', '%1%2')

  -- Decode each encoded-word
  s = s:gsub('=%?([^?]+)%?([BbQq])%?([^?]+)%?=', function(charset, enc, text)
    local decoded = decode_word(charset, enc, text)
    return decoded or ('=?' .. charset .. '?' .. enc .. '?' .. text .. '?=')
  end)

  return s
end

--- Encodes a string into an RFC 2047 encoded-word ("=?utf-8?B?...?=")
--- if it contains any non-ASCII (byte >= 128) characters.
---@param text string|nil
---@return string|nil
local encode_rfc2047_word = function(text)
  if not text or text == '' then
    return text
  end
  local has_non_ascii = false
  for i = 1, #text do
    if text:byte(i) >= 128 then
      has_non_ascii = true
      break
    end
  end
  if not has_non_ascii then
    return text
  end
  local base64 = require('notmuch.base64')
  return '=?utf-8?B?' .. base64.encode(text) .. '?='
end

--- Prepares a header value for RFC 5322/2047 transmission.
--- Encodes non-ASCII characters into UTF-8 Base64 encoded-words. For address
--- headers (From, To, Cc, Bcc) only the display-name is encoded, keeping
--- the `<user@domain>` bracketed address in pure ASCII.
---@param header_name string
---@param value string|nil
---@return string|nil
local encode_header_for_send = function(header_name, value)
  if not value or value == '' then
    return value
  end
  local lower = header_name:lower()

  -- Address headers: encode each display name, keep <addr> as pure ASCII
  if lower == 'from' or lower == 'to' or lower == 'cc' or lower == 'bcc' then
    local parts = vim.split(value, ',', { plain = true })
    for i, part in ipairs(parts) do
      local name, addr = part:match('^%s*(.-)%s*(<[^>]+>)%s*$')
      if name and addr then
        if name:match('^".*"$') then
          name = name:sub(2, -2)
        end
        parts[i] = encode_rfc2047_word(name) .. ' ' .. addr
      else
        parts[i] = encode_rfc2047_word(vim.trim(part))
      end
    end
    return table.concat(parts, ', ')
  end

  -- Structured headers that must remain pure ASCII:
  if lower == 'message-id' or lower == 'in-reply-to' or lower == 'references'
      or lower == 'content-type' or lower == 'mime-version'
      or lower == 'content-transfer-encoding' then
    return value
  end

  -- Default (Subject, etc.): encode if contains non-ASCII
  return encode_rfc2047_word(value)
end

--- Normalizes RFC 5322 header table by encoding any non-ASCII values with
--- RFC 2047 so outgoing messages comply with SMTP standards.
---@param attributes table<string, string>
---@return table<string, string>
local sanitize_attributes_for_send = function(attributes)
  local out = {}
  for k, v in pairs(attributes or {}) do
    out[k] = encode_header_for_send(k, v)
  end
  return out
end

--- Removes the user's own address from a comma-separated recipient header (To/Cc)
--- so replying to a message does not add the user as recipient of their own email.
---@param header_val string|nil
---@param self_addr string|nil
---@return string
local filter_self_from_header = function(header_val, self_addr)
  if not header_val or header_val == '' or not self_addr or self_addr == '' then
    return header_val or ''
  end
  local self_clean = self_addr:lower():match('<([^>]+)>')
      or self_addr:lower():match('%S+@%S+')
      or self_addr:lower()
  local parts = vim.split(header_val, ',', { plain = true })
  local kept = {}
  for _, p in ipairs(parts) do
    local trimmed = vim.trim(p)
    if trimmed ~= '' then
      local email = trimmed:lower():match('<([^>]+)>')
          or trimmed:lower():match('%S+@%S+')
          or trimmed:lower()
      if email ~= self_clean then
        table.insert(kept, trimmed)
      end
    end
  end
  return table.concat(kept, ', ')
end

--- Cleans up whitespace in Subject lines (e.g. Outlook's 40+ leading spaces
--- after "RE: / RV: ") while preserving the prefix.
---@param subject string|nil
---@return string|nil
local clean_subject_whitespace = function(subject)
  if not subject or subject == '' then
    return subject
  end
  local prefix, rest = subject:match('^([Rr][Ee][:%s]+)(.*)$')
  if not prefix then
    prefix, rest = subject:match('^([Rr][Vv][:%s]+)(.*)$')
  end
  if prefix and rest then
    return vim.trim(prefix) .. ' ' .. vim.trim(rest:gsub('%s+', ' '))
  end
  return vim.trim(subject:gsub('%s+', ' '))
end

-- exposed for tests / debugging
s._resolve_from = resolve_from
s._decode_rfc2047 = decode_rfc2047
s._encode_header_for_send = encode_header_for_send
s._detect_received_identity = detect_received_identity
s._filter_self_from_header = filter_self_from_header
s._clean_subject_whitespace = clean_subject_whitespace

--- Returns true if signature_file is an HTML file (.html/.htm).
local is_html_signature = function()
  local path = config.options.signature_file
  if not path or path == '' then
    return false
  end
  return path:lower():match('%.html?$') ~= nil
end

--- Simple HTML tag stripper for plain fallback (keeps text, drops tags).
local html_to_text = function(html)
  local text = html
  -- Convert block/break tags to newlines before stripping
  text = text:gsub('<[Bb][Rr][^>]*>', '\n')
  text = text:gsub('</[Pp]>', '\n'):gsub('<[Pp][^>]*>', '')
  text = text:gsub('</[Dd][Ii][Vv]>', '\n'):gsub('<[Dd][Ii][Vv][^>]*>', '\n')
  text = text:gsub('</[Hh][1-6]>', '\n'):gsub('<[Hh][1-6][^>]*>', '\n')
  text = text:gsub('<[^>]+>', '')
  text = text:gsub('&nbsp;', ' '):gsub('&amp;', '&'):gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&quot;', '"')
  -- Collapse multiple blank lines and trim
  text = text:gsub('\r', '')
  text = text:gsub('^%s+', ''):gsub('%s+$', '')
  text = text:gsub('\n[ \t]+', '\n')
  text = text:gsub('\n%s*\n', '\n\n')
  return text
end

--- Reads HTML signature and rewrites <img src="..."> to cid:..., collecting images.
--- Follows Outlook pattern: inline images via Content-ID in multipart/related.
--- @return string|nil html_rewritten, table|nil inline_images [{path,cid}]
local get_html_signature_data = function()
  if not is_html_signature() then
    return nil, nil
  end
  local path = vim.fn.expand(config.options.signature_file)
  if vim.fn.filereadable(path) == 0 then
    vim.notify('notmuch.nvim: signature_file not readable: ' .. path, vim.log.levels.WARN)
    return nil, nil
  end
  local fh, err = io.open(path, 'r')
  if not fh then
    vim.notify('notmuch.nvim: failed to read signature_file: ' .. (err or path), vim.log.levels.WARN)
    return nil, nil
  end
  local raw = fh:read('*a')
  fh:close()
  if not raw or raw:match('^%s*$') then
    return nil, nil
  end

  local inline_images = {}
  local cid_counter = 0
  -- Rewrite src="local/path" -> src="cid:..."
  local rewritten = raw:gsub('<[Ii][Mm][Gg][^>]*[Ss][Rr][Cc]%s*=%s*["\']([^"\']+)["\']', function(src)
    -- Skip already cid: or http(s):// or data:
    if src:match('^cid:') or src:match('^https?://') or src:match('^data:') then
      return '<img src="' .. src .. '"'
    end
    local img_path = vim.fn.expand(src)
    -- If src is relative, try relative to signature file dir
    if vim.fn.filereadable(img_path) == 0 then
      local sig_dir = vim.fn.fnamemodify(path, ':h')
      local try2 = sig_dir .. '/' .. src
      if vim.fn.filereadable(try2) == 1 then
        img_path = try2
      else
        vim.notify('notmuch.nvim: signature image not found: ' .. src, vim.log.levels.WARN)
        return '<img src="' .. src .. '"'
      end
    end
    cid_counter = cid_counter + 1
    local cid = string.format('sig-img-%d@notmuch.nvim', cid_counter)
    table.insert(inline_images, { path = img_path, cid = cid })
    return '<img src="cid:' .. cid .. '"'
  end)

  -- Also handle single-quoted variant already covered; ensure double handling for src without quotes (rare)
  return rewritten, inline_images
end

--- Reads signature file if configured, returns lines to append (with delimiter).
--- For .html signatures, returns plain-text fallback (stripped tags) for compose buffer.
--- Handles leading/trailing blank trimming and avoids duplicating "-- " if
--- the file already starts with it. Warns if file is not readable.
--- @return string[]|nil: lines to append (e.g. {"", "-- ", "sig line", ...})
local get_signature_lines = function()
  local path = config.options.signature_file
  if not path or path == '' then
    return nil
  end
  -- HTML signature: provide plain text fallback for compose buffer
  if is_html_signature() then
    local html, _ = get_html_signature_data()
    if not html then
      return nil
    end
    local text = html_to_text(html)
    if text == '' then
      return nil
    end
    local lines = vim.split(text, '\n', { plain = true })
    -- Trim leading/trailing blanks like plain case
    local start = 1
    while start <= #lines and lines[start]:match('^%s*$') do
      start = start + 1
    end
    local finish = #lines
    while finish >= start and lines[finish]:match('^%s*$') do
      finish = finish - 1
    end
    if start > finish then
      return nil
    end
    local sig = {}
    for i = start, finish do
      table.insert(sig, lines[i])
    end
    local out = { '', '-- ' }
    for _, l in ipairs(sig) do
      table.insert(out, l)
    end
    return out
  end

  path = vim.fn.expand(path)
  if vim.fn.filereadable(path) == 0 then
    vim.notify('notmuch.nvim: signature_file not readable: ' .. path, vim.log.levels.WARN)
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines then
    vim.notify('notmuch.nvim: failed to read signature_file: ' .. path, vim.log.levels.WARN)
    return nil
  end
  -- Trim leading/trailing blank lines but preserve internal blanks
  local start = 1
  while start <= #lines and lines[start]:match('^%s*$') do
    start = start + 1
  end
  local finish = #lines
  while finish >= start and lines[finish]:match('^%s*$') do
    finish = finish - 1
  end
  if start > finish then
    return nil
  end
  local sig = {}
  for i = start, finish do
    table.insert(sig, lines[i])
  end
  local has_delim = sig[1] == '-- ' or sig[1] == '--'
  local out = { '' }
  if not has_delim then
    table.insert(out, '-- ')
  end
  for _, l in ipairs(sig) do
    table.insert(out, l)
  end
  return out
end

--- Escape plain text for HTML and convert newlines to <br>.
local plain_to_html = function(s)
  s = s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
  s = s:gsub('\n', '<br>\n')
  return s
end

--- Builds Outlook-style body: multipart/alternative with plain + html(+related images).
--- Returns mime_table fragment for body (to be inserted into multipart/mixed or top-level).
local build_html_body_mime = function(plain_lines, html_sig_rewritten, inline_images)
  -- plain_lines: body lines including plain signature fallback (already in msg)
  -- html_sig_rewritten: html string with cid: rewritten
  local body_text = table.concat(plain_lines, '\n')
  -- Split body_text at signature delimiter for HTML composition (plain search, "-"" is magic in patterns)
  local delim_pos = body_text:find('\n-- \n', 1, true)
  -- If user removed signature delimiter from compose buffer, don't inject
  -- HTML signature (or its inline images) into the outgoing MIME.
  if not delim_pos then
    html_sig_rewritten = nil
    inline_images = nil
  end
  local body_only = body_text
  if delim_pos then
    body_only = body_text:sub(1, delim_pos - 1)
  end
  -- Trim leading newline from body_only (msg starts with "" after headers)
  body_only = body_only:gsub('^\n', '')
  local body_html = plain_to_html(body_only)
  local html_content
  if html_sig_rewritten then
    html_content = '<html><body>\n' .. body_html .. '\n<br><br>\n' .. html_sig_rewritten .. '\n</body></html>'
  else
    html_content = '<html><body>\n' .. body_html .. '\n</body></html>'
  end

  local plain_mime = {
    type = 'text/plain; charset=utf-8',
    content = table.concat(plain_lines, '\n'),
    encoding = '8bit',
    attachment = false,
  }
  local html_mime = {
    type = 'text/html; charset=utf-8',
    content = html_content,
    encoding = '8bit',
    attachment = false,
  }

  if inline_images and #inline_images > 0 then
    local related_mimes = { html_mime }
    for _, img in ipairs(inline_images) do
      table.insert(related_mimes, {
        file = img.path,
        type = m.get_mime_type(img.path),
        cid = img.cid,
        attachment = false,
        encoding = 'base64',
        filename = vim.fn.fnamemodify(img.path, ':t'),
      })
    end
    return {
      type = 'multipart/alternative',
      mime = {
        plain_mime,
        {
          type = 'multipart/related',
          mime = related_mimes,
        },
      },
    }
  else
    return {
      type = 'multipart/alternative',
      mime = { plain_mime, html_mime },
    }
  end
end

--- Returns the persistent drafts directory, creating it if needed.
---
--- Falls back to nil when no draft_dir is configured, so callers can fall
--- back to per-session temp files.
---
--- @return string|nil: absolute path to the drafts directory
local get_draft_dir = function()
  local dir = config.options.draft_dir
  if not dir or dir == '' then
    return nil
  end

  vim.fn.mkdir(dir, 'p')
  return dir
end

--- Builds a timestamped draft file path inside the drafts directory.
---
--- Falls back to a per-session temp name when draft_dir is not configured.
--- Guarantees a non-existent path even when called twice within one second.
---
--- @param prefix string: filename prefix, e.g. 'compose' or 'reply'
--- @return string: absolute path to a new draft file
local new_draft_path = function(prefix)
  local dir = get_draft_dir()
  if not dir then
    return vim.fn.tempname() .. '-' .. prefix .. '.eml'
  end

  local stamp = os.date('%Y%m%d-%H%M%S')
  local path = string.format('%s/%s-%s.eml', dir, prefix, stamp)

  local n = 1
  while u.file_exists(path) do
    n = n + 1
    path = string.format('%s/%s-%s-%d.eml', dir, prefix, stamp, n)
  end

  return path
end

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
--- (not MIME `multipart/mixed`) of type `text/plain; charset=UTF-8`, or
--- Outlook-style `multipart/alternative` (+ `multipart/related` for HTML signature images) when `signature_file` is `.html`.
---
--- @param buf integer: buffer ID of the message compose file
local build_plain_msg = function(buf)
  local main_lines = v.nvim_buf_get_lines(buf, 0, -1, false)

  local attributes, msg = m.get_msg_attributes(main_lines)
  -- Ensure headers comply with RFC 2047 before sending
  attributes = sanitize_attributes_for_send(attributes)
  v.nvim_buf_set_lines(buf, 0, -1, false, msg)
  vim.cmd('silent! write!')

  if is_html_signature() then
    local html_sig, inline_images = get_html_signature_data()
    -- Build Outlook-style alternative body (plain + html + inline images)
    local body_alt = build_html_body_mime(msg, html_sig, inline_images)
    local mime_table = {
      version = 'MIME-Version: 1.0',
      type = body_alt.type,
      encoding = '8bit',
      attributes = attributes,
      mime = body_alt.mime,
    }
    local mime_msg = m.make_mime_msg(mime_table)
    v.nvim_buf_set_lines(buf, 0, -1, false, mime_msg)
    vim.cmd('silent! write!')
    return
  end

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
--- When `signature_file` is `.html`, body is Outlook-style `multipart/alternative` (+ `related` for images) as first part of `multipart/mixed`.
---
--- @param buf integer: buffer ID of the message compose file
--- @param attachment_paths table: list of absolute file path strings
--- @param message_filename string: path to the composed message file
local build_mime_msg_from_attachments = function(buf, attachment_paths, message_filename)
  local main_lines = v.nvim_buf_get_lines(buf, 0, -1, false)

  local attributes, msg = m.get_msg_attributes(main_lines)
  -- Ensure headers comply with RFC 2047 before sending
  attributes = sanitize_attributes_for_send(attributes)

  -- Validate attachments BEFORE modifying buffer/file
  local attachments = m.create_mime_attachments(attachment_paths)

  -- Safe to modify buffer now
  v.nvim_buf_set_lines(buf, 0, -1, false, msg)
  vim.cmd('silent! write!')

  local mimes
  if is_html_signature() then
    local html_sig, inline_images = get_html_signature_data()
    local body_alt = build_html_body_mime(msg, html_sig, inline_images)
    mimes = { body_alt }
    for _, attachment in ipairs(attachments) do
      table.insert(mimes, attachment)
    end
  else
    mimes = { {
      file = message_filename,
      type = "text/plain; charset=utf-8",
    } }
    for _, attachment in ipairs(attachments) do
      table.insert(mimes, attachment)
    end
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
        -- Draft was sent successfully; clean up the draft file so unsent
        -- drafts are the only ones that persist across sessions.
        pcall(os.remove, filename)
        vim.defer_fn(function()
          vim.notify('Email sent successfully', vim.log.levels.INFO)
        end, 500)
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

  -- Draft lives in the persistent drafts dir (falls back to a per-session
  -- temp name when draft_dir is unset) so it survives across Neovim sessions.
  local draft_dir = get_draft_dir() or vim.fn.stdpath('data') .. '/notmuch/drafts'
  local reply_filename = draft_dir .. '/reply-' .. sanitized_thread .. '-' .. sanitized_id .. '.eml'

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

  if draft_exists then
    -- When reopening an existing draft (saved on disk before our decode fix,
    -- or containing raw RFC2047 words / excessive whitespace), clean up headers
    -- so the user always sees clean, human-readable text.
    local rlines = v.nvim_buf_get_lines(buf, 0, -1, false)
    local header_end = nil
    for i, line in ipairs(rlines) do
      if line == '' then
        header_end = i
        break
      end
    end
    if header_end then
      local logical_headers = {}
      for i = 1, header_end - 1 do
        local line = rlines[i]
        if line:match('^[ \t]') and #logical_headers > 0 then
          local prev = logical_headers[#logical_headers]
          prev.value = prev.value .. ' ' .. vim.trim(line)
        else
          local key, val = line:match('^([^:]+):%s*(.*)$')
          if key then
            table.insert(logical_headers, { key = key, value = val })
          end
        end
      end

      local new_headers = {}
      local changed = false
      for _, h in ipairs(logical_headers) do
        local k_lower = h.key:lower()
        local val = decode_rfc2047(h.value)
        if k_lower == 'from' and val:find('jgp@localhost') then
          val = resolve_from(id)
          changed = true
        end
        if k_lower == 'subject' then
          local cleaned = clean_subject_whitespace(val)
          if cleaned ~= val then
            val = cleaned
            changed = true
          end
        end
        if val ~= h.value then
          changed = true
        end
        table.insert(new_headers, h.key .. ': ' .. val)
      end

      if changed or #new_headers ~= (header_end - 1) then
        local combined = {}
        for _, h in ipairs(new_headers) do
          table.insert(combined, h)
        end
        for i = header_end, #rlines do
          table.insert(combined, rlines[i])
        end
        v.nvim_buf_set_lines(buf, 0, -1, false, combined)
        vim.cmd('silent write')
      end
    end
  else
    -- Fresh reply: populate from notmuch reply output.
    -- Default to replying to all participants, with filter_self_from_header
    -- removing the user's own address from the initial template.
    vim.cmd('silent 0read! notmuch reply --reply-to=all id:' .. id)

    -- Clean up headers produced by `notmuch reply`:
    -- 1. Unfold multiline RFC 5322 continuation lines so values like
    --    "To: A,\n\tB" are parsed as a single header.
    -- 2. Decode RFC 2047 encoded-words across all headers (Subject, etc.).
    -- 3. Detect the exact address where the user received this email (fallback
    --    to from_cmd / config.options.from) and set it in From.
    -- 4. Filter out the user's own address from To and Cc when building the
    --    initial template, keeping all other recipients intact. If the user
    --    manually types their address back into To/Cc later, it will be sent.
    do
      local from = resolve_from(id)
      local rlines = v.nvim_buf_get_lines(buf, 0, -1, false)
      local header_end = nil
      for i, line in ipairs(rlines) do
        if line == '' then
          header_end = i
          break
        end
      end
      if header_end then
        local logical_headers = {}
        for i = 1, header_end - 1 do
          local line = rlines[i]
          if line:match('^[ \t]') and #logical_headers > 0 then
            local prev = logical_headers[#logical_headers]
            prev.value = prev.value .. ' ' .. vim.trim(line)
          else
            local key, val = line:match('^([^:]+):%s*(.*)$')
            if key then
              table.insert(logical_headers, { key = key, value = val })
            end
          end
        end

        local new_headers = {}
        for _, h in ipairs(logical_headers) do
          local k_lower = h.key:lower()
          if k_lower == 'from' then
            table.insert(new_headers, 'From: ' .. from)
          else
            local val = decode_rfc2047(h.value)
            if k_lower == 'subject' then
              val = clean_subject_whitespace(val)
              table.insert(new_headers, 'Subject: ' .. val)
            elseif k_lower == 'to' then
              val = filter_self_from_header(val, from)
              if val ~= '' then
                table.insert(new_headers, 'To: ' .. val)
              end
            elseif k_lower == 'cc' then
              val = filter_self_from_header(val, from)
              if val ~= '' then
                table.insert(new_headers, 'Cc: ' .. val)
              end
            else
              table.insert(new_headers, h.key .. ': ' .. val)
            end
          end
        end

        local combined = {}
        for _, h in ipairs(new_headers) do
          table.insert(combined, h)
        end
        for i = header_end, #rlines do
          table.insert(combined, rlines[i])
        end
        v.nvim_buf_set_lines(buf, 0, -1, false, combined)
      end
    end

    if not config.options.include_original_response then
      -- Strip quoted original message when include_original_response = false.
      -- notmuch reply emits headers, a blank line, then the quoted body starting
      -- with an "On ... wrote:" line followed by "> " prefixed lines.
      -- We keep the headers + blank line and drop everything after.
      local lines = v.nvim_buf_get_lines(buf, 0, -1, false)
      local keep_until = #lines -- default: keep all
      local past_headers = false
      for i, line in ipairs(lines) do
        if not past_headers then
          if line == '' then
            past_headers = true
          end
        else
          if line:match('^On ') or line:match('^>') then
            keep_until = i - 1
            break
          end
        end
      end
      while keep_until > 1 and lines[keep_until] == '' do
        keep_until = keep_until - 1
      end
      local kept = vim.list_slice(lines, 1, keep_until)
      table.insert(kept, '') -- single blank line after headers for typing body
      v.nvim_buf_set_lines(buf, 0, -1, false, kept)
      vim.cmd('silent write')
    else
      -- include_original_response = true: quoted text stays as sendable body,
      -- but persist the normalized headers to the draft.
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
  local compose_filename = new_draft_path('compose')

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

  -- Append signature if configured (new mails only)
  local sig_lines = get_signature_lines()
  if sig_lines then
    for _, l in ipairs(sig_lines) do
      table.insert(headers, l)
    end
  end

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
