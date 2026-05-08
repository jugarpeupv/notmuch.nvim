--- notmuch.images -- Inline CID image rendering for notmuch.nvim
---
--- Uses image.nvim (https://github.com/3rd/image.nvim) to render images
--- that are embedded in email HTML bodies as CID references, e.g.:
---   [cid:image037.png@01DCDEC5.3FD59DC0]
---
--- Call render_inline_images(buf, win, inline_images) after the thread
--- buffer has been populated.  Each entry in inline_images is produced by
--- thread.get_inline_images() and has the shape:
---   { line = <1-based line in lines[] before header offset>,
---     msg_id = <notmuch message id string>,
---     filename = <bare filename, e.g. "image037.png">,
---     part_id = <notmuch part number integer> }
---
--- The HEADER_OFFSET (2 lines: hints + blank) is applied here so callers
--- don't need to know about it.
---
--- Performance: each MIME part is extracted with a non-blocking vim.system()
--- call.  All extractions are launched concurrently; images are rendered as
--- each extraction completes, so the thread buffer is displayed immediately
--- and images pop in asynchronously.

local M = {}

--- Constant matching the HEADER_OFFSET used in init.lua / thread.lua
local HEADER_OFFSET = 2

--- Returns true when path looks like a renderable image.
---@param path string
---@return boolean
local function is_image_path(path)
  return path:match('%.[pP][nN][gG]$') ~= nil
    or path:match('%.[jJ][pP][eE]?[gG]$') ~= nil
    or path:match('%.[gG][iI][fF]$') ~= nil
    or path:match('%.[wW][eE][bB][pP]$') ~= nil
    or path:match('%.[aA][vV][iI][fF]$') ~= nil
end

--- Returns the temp file path used for a given part extraction.
---@param part_id number
---@param filename string
---@return string
local function temp_path(part_id, filename)
  local safe_name = filename:gsub('/', '-')
  return '/tmp/notmuch_cid_' .. part_id .. '_' .. safe_name
end

--- Asynchronously extracts a notmuch MIME part to a temp file, then calls
--- on_done(filepath) on success or on_done(nil) on failure.
---
---@param msg_id  string   Notmuch message ID
---@param part_id number   Notmuch part number
---@param filename string  Original filename (used as temp file basename)
---@param on_done fun(filepath: string|nil)
local function extract_part_async(msg_id, part_id, filename, on_done)
  local filepath = temp_path(part_id, filename)

  -- Use the shell so we can redirect stdout to the file.
  -- vim.system() with cmd array cannot redirect, so we wrap in sh -c.
  local cmd = string.format(
    "notmuch show --exclude=false --part=%d 'id:%s' > %s",
    part_id,
    msg_id,
    vim.fn.shellescape(filepath)
  )

  vim.system({ 'sh', '-c', cmd }, { text = false }, function(result)
    -- This callback runs on the main loop via vim.schedule internally in
    -- Neovim >= 0.10; schedule explicitly for safety on older builds.
    vim.schedule(function()
      if result.code ~= 0 then
        on_done(nil)
      else
        on_done(filepath)
      end
    end)
  end)
end

--- Renders a single image into the buffer at the given row.
---@param image_api table  The required('image') API object
---@param buf       number Buffer number
---@param win       number Window number
---@param filepath  string Absolute path to the image file
---@param entry     table  Inline-image record {line, msg_id, filename, part_id}
local function render_one(image_api, buf, win, filepath, entry)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
    return
  end

  -- Convert lines[]-relative line to 0-based buffer row for image.nvim.
  -- entry.line is the 1-based absolute position in the global lines[] accumulator
  -- (set correctly by process_body_parts using line_offset).
  -- After prepending HEADER_OFFSET lines, 0-based buffer row for the cid line is:
  --   (entry.line - 1) + HEADER_OFFSET
  -- We render the image on the line *after* [cid:...], so +1:
  --   y = entry.line + HEADER_OFFSET
  local y = entry.line + HEADER_OFFSET

  local img = image_api.from_file(filepath, {
    id = string.format('notmuch_cid_%s_%d', entry.msg_id:gsub('[^%w]', '_'), entry.part_id),
    window = win,
    buffer = buf,
    inline = true,
    -- Insert virtual-padding extmarks so text below the image is pushed down
    -- and the image doesn't overlap it.
    with_virtual_padding = true,
    x = 0,
    y = y,
    max_width_window_percentage = 80,
    max_height_window_percentage = 25,
  })

  if img then
    img:render()
  else
    vim.notify(
      'notmuch.images: image.nvim could not load: ' .. filepath,
      vim.log.levels.WARN
    )
  end
end

--- Renders all inline CID images into the thread buffer using image.nvim.
---
--- Extractions are performed concurrently (non-blocking vim.system calls).
--- The thread buffer is shown immediately; images pop in as each extraction
--- completes.
---
---@param buf           number    Buffer number of the thread buffer
---@param win           number    Window number that shows the thread buffer
---@param inline_images table[]   List from thread.get_inline_images()
---@return nil
M.render_inline_images = function(buf, win, inline_images)
  if not inline_images or #inline_images == 0 then
    return
  end

  local ok, image_api = pcall(require, 'image')
  if not ok then
    -- image.nvim not installed; silently skip
    return
  end

  -- Count how many CIDs share each line. Lines with multiple CIDs (e.g. a row
  -- of social-media icons) are skipped for rendering — they would stack or
  -- consume excessive vertical space. gx still works for those entries.
  local cids_per_line = {}
  for _, entry in ipairs(inline_images) do
    cids_per_line[entry.line] = (cids_per_line[entry.line] or 0) + 1
  end

  for _, entry in ipairs(inline_images) do
    if cids_per_line[entry.line] > 1 then
      -- Multiple CIDs on this line — skip rendering, gx still works
    elseif not is_image_path(entry.filename) then
      -- Not a renderable image format (pdf, doc, …) – skip
    else
      extract_part_async(entry.msg_id, entry.part_id, entry.filename, function(filepath)
        if not filepath then
          vim.notify(
            string.format('notmuch.images: failed to extract part %d of id:%s',
              entry.part_id, entry.msg_id),
            vim.log.levels.WARN
          )
          return
        end
        render_one(image_api, buf, win, filepath, entry)
      end)
    end
  end
end

--- Opens a CID inline image using the configured open_handler.
--- If the temp file already exists (extracted during rendering) it is opened
--- immediately; otherwise the part is extracted first, then opened.
---
---@param entry table  Inline-image record {line, msg_id, filename, part_id}
---@return nil
M.open_cid = function(entry)
  local path = temp_path(entry.part_id, entry.filename)

  local function do_open()
    require('notmuch.config').options.open_handler({ path = path })
  end

  -- Check if already extracted
  local stat = vim.uv.fs_stat(path)
  if stat then
    do_open()
    return
  end

  -- Not yet extracted — extract asynchronously then open
  extract_part_async(entry.msg_id, entry.part_id, entry.filename, function(filepath)
    if not filepath then
      vim.notify(
        string.format('notmuch.images: failed to extract part %d of id:%s',
          entry.part_id, entry.msg_id),
        vim.log.levels.WARN
      )
      return
    end
    do_open()
  end)
end

--- Clears all images previously rendered into a buffer.
---@param buf number Buffer number
---@return nil
M.clear_images = function(buf)
  local ok, image_api = pcall(require, 'image')
  if not ok then return end

  local images = image_api.get_images({ buffer = buf })
  if images then
    for _, img in ipairs(images) do
      pcall(function() img:clear() end)
    end
  end
end

return M
