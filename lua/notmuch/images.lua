--- notmuch.images -- CID image extraction for notmuch.nvim
---
--- Provides gx support: when the cursor is on a [cid:filename@...] token in a
--- thread buffer, open_cid() extracts the MIME part and opens it with the
--- configured system handler (open / xdg-open).
---
--- In-buffer rendering via image.nvim has been intentionally removed.
--- Use the 'a' attachment browser + open HTML in browser to view images.

local M = {}

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
---@param msg_id  string
---@param part_id number
---@param filename string
---@param on_done fun(filepath: string|nil)
local function extract_part_async(msg_id, part_id, filename, on_done)
  local filepath = temp_path(part_id, filename)

  local cmd = string.format(
    "notmuch show --exclude=false --part=%d 'id:%s' > %s",
    part_id,
    msg_id,
    vim.fn.shellescape(filepath)
  )

  vim.system({ 'sh', '-c', cmd }, { text = false }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        on_done(nil)
        return
      end
      local stat = vim.uv.fs_stat(filepath)
      if not stat or stat.size == 0 then
        on_done(nil)
        return
      end
      on_done(filepath)
    end)
  end)
end

--- Opens a CID inline image using the configured open_handler.
--- If the temp file already exists it is opened immediately; otherwise the
--- part is extracted first, then opened.
---@param entry table  {line, msg_id, filename, part_id}
M.open_cid = function(entry)
  local path = temp_path(entry.part_id, entry.filename)

  local function do_open()
    require('notmuch.config').options.open_handler({ path = path })
  end

  local stat = vim.uv.fs_stat(path)
  if stat and stat.size > 0 then
    do_open()
    return
  end

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

return M
