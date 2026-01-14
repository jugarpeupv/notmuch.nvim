local T = {}

--- Recursively checks MIME tree for parts with filenames (attachments)
--- @param body table Array of body part objects from notmuch JSON output
--- @return boolean, integer
local function has_attachments(body)
  if not body or #body == 0 then
    return false, 0
  end

  local count = 0

  -- Recursively walk the MIME tree and check for `filename` for attachments
  local function walk(parts)
    for _, part in ipairs(parts) do
      if part.filename then
        count = count + 1
      end
      if type(part.content) == "table" then
        walk(part.content)
      end
    end
  end

  walk(body)
  return count > 0, count
end

--- Indents a summary line based on depth in thread reply chain
--- @param line string Line to indent
--- @param depth number Reply depth (0 for root)
--- @return string indented Indented line with depth prefix
local function indent_line(line, depth)
  if depth == 0 then
    return line
  end
  return string.rep('────', depth) .. line
end

--- Formats message headers into buffer lines
--- Creates the summary line and detailed headers
--- @param msg table Message object from notmuch JSON output
--- @param depth number Message depth in thread chain for indentation
--- @return table Array of formatted header lines
local function format_headers(msg, depth)
  local lines = {}
  local headers = msg.headers or {}

  -- Extract header values with fallbacks
  local from = headers.From or "[Unknown sender]"
  local subject = headers.Subject or "[No subject]"
  local to = headers.To or ""
  local cc = headers.Cc
  local date_full = headers.Date or ""
  local date_relative = msg.date_relative or ""

  -- Get tags and attachment info
  local tags = msg.tags or {}
  local tags_str = table.concat(tags, " ")
  local has_attach, attach_count = has_attachments(msg.body)

  -- Format summary line with indendation depth indicator
  local summary = string.format("%s (%s) (%s)", from, date_relative, tags_str)
  table.insert(lines, indent_line(summary, depth))

  -- Fold start marker with message ID
  table.insert(lines, string.format("id:%s {{{", msg.id))

  -- Add detailed headers
  table.insert(lines, "Subject: " .. subject)
  table.insert(lines, "From: " .. from)
  if to ~= "" then
    table.insert(lines, "To: " .. to)
  end
  if cc then
    table.insert(lines, "Cc: " .. cc)
  end
  table.insert(lines, "Date: " .. date_full)

  -- Add attachment indicator if applicable
  if has_attach then
    table.insert(lines, string.format("📎 %d attachment%s", attach_count, attach_count > 1 and "s" or ""))
  end

  -- Blank link after headers
  table.insert(lines, "")

  return lines
end

--- Processes the MIME body parts and adds them to buffer lines
---
--- Walks the MIME tree and handles each part type appropriately:
--- - multipart/*: Recurses into child parts
--- - text/* (inline): Adds content directly
--- - attachments (with filename): Adds marker with filename and hint
--- - other inline (images, etc): Adds type marker
---
--- @param body table MIME part objects from notmuch JSON output
--- @return table lines Array of buffer lines for the message body
local function process_body_parts(body)
  local lines = {}

  local function walk(parts, parent_type)
    for _, part in ipairs(parts) do
      local content_type = part['content-type'] or ''

      if content_type:match('^multipart/') then
        -- Multipart envelope -> recurse through child parts
        walk(part.content, content_type)

      elseif part.filename then
        -- Definitely an attachment -> display to user and hint for viewing
        table.insert(lines, string.format(
          "[ 📎 %s (%s) - press 'a' to view attachments ]",
          part.filename, content_type
        ))
        table.insert(lines, "")

      elseif content_type == 'text/plain' and part.content then
        -- Always show inline plain text (including signatures, etc.)
        for _, line in ipairs(vim.split(part.content, '\n', { plain = true })) do
          table.insert(lines, line)
        end

      elseif content_type == 'text/html' then
        -- In multipart/alternative, skip HTML (plain text is preferred)
        -- Otherwise, show marker for standalone HTML
        if parent_type == 'multipart/alternative' then
          table.insert(lines, "[ text/html (alternative) - press 'a' to view ]")
          table.insert(lines, "")
        else
          table.insert(lines, "[ text/html (hidden) - press 'a' to view ]")
          table.insert(lines, "")
        end

      elseif part.content then
        table.insert(lines, string.format("[ %s (inline) - press 'a' to view attachments ]", content_type))
        table.insert(lines, "")
      end
    end
  end

  walk(body, nil)
  return lines
end

--- Recursively processes a message and its replies into buffer lines
--- @param msg_node table Message node from notmuch JSON: [msg, [replies]]
--- @param depth number Message depth in the thread chain (0 for root message)
--- @param lines table Accumulator array for buffer lines (modified in place)
local function build_message_lines(msg_node, depth, lines)
  -- Unpack msg_node into message and list of replies
  local msg = msg_node[1]
  local replies = msg_node[2] or {}

  -- Parse and prepare header lines
  local headers = format_headers(msg, depth)
  vim.list_extend(lines, headers)

  -- Extract body and content
  local body = process_body_parts(msg.body)
  vim.list_extend(lines, body)

  -- Add fold end marker
  table.insert(lines, "}}}")

  -- Add blank line separator after message
  table.insert(lines, "")

  -- Process replies recursively
  if replies and #replies > 0 then
    for _, reply_node in ipairs(replies) do
      build_message_lines(reply_node, depth + 1, lines)
    end
  end
end

T.show_thread = function(threadid)
  -- Run `notmuch show` with JSON format
  local res = vim.system({
    'notmuch', 'show',
    '--format=json',
    '--exclude=false',
    'thread:' .. threadid
  }):wait()

  -- Check for `notmuch show` execution error
  if res.code ~= 0 then
    vim.notify(
      'Error running notmuch show: ' .. (res.stderr or 'unknown error'),
      vim.log.levels.ERROR
    )
    return { "Error: Could not fetch thread data" }
  end

  -- Check for empty result output
  if res.stdout == "[]\n" or res.stdout == "" then
    return { "Thread not found or empty" }
  end

  -- Parse/decode JSON output
  local ok, json = pcall(vim.json.decode, res.stdout)
  if not ok then
    vim.notify(
      'Failed to parse thread JSON: ' .. tostring(json),
      vim.log.levels.ERROR
    )
    return { "Error: Could not parse thread data" }
  end

  -- Validate JSON structure
  if not json or #json == 0 or not json[1] or #json[1] == 0 or not json[1][1] then
    return { "Thread data is malformed or empty" }
  end

  -- Extract root message node:
  -- [                    -- Array of threads
  --   [                  -- Thread (single element for `notmuch show thread:X`)
  --     [                -- Message tree (array of messages at same depth)
  --       {              -- Message object (root message)
  --         "id": "...",
  --         "headers": {...},
  --         "body": [...],
  --         "replies": [...]
  --       }
  --     ]
  --   ]
  -- ]
  --
  -- TL;DR:
  -- json[1][1] is the root node -> [message_object, [replies_array]]
  local root_node = json[1][1]

  -- Build buffer lines
  local lines = {}
  build_message_lines(root_node, 0, lines)

  return lines
end

return T
