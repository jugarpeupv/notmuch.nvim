--- Validation and normalization for streamed `notmuch search` records.
local M = {}

--- Validate and normalize one decoded search record.
---@param record any
---@param i integer
---@param seen table<string, boolean>
function M.validate_record(record, i, seen)
  local function invalid(field)
    return nil, ("Invalid search record %d (%s)"):format(i, field)
  end

  if type(record) ~= "table" then
    return invalid("object")
  end

  -- Thread IDs are unique 16-character hexadecimal strings.
  if
    type(record.thread) ~= "string"
    or not record.thread:match("^[0-9a-fA-F]+$")
    or seen[record.thread]
  then
    return invalid("thread ID")
  end
  seen[record.thread] = true

  for _, field in ipairs({ "matched", "total" }) do
    local n = record[field]
    if type(n) ~= "number" or n < 0 or n == math.huge or n ~= math.floor(n) then
      return invalid(field)
    end
  end

  for _, field in ipairs({ "authors", "subject", "date_relative" }) do
    if record[field] == nil or record[field] == vim.NIL then
      record[field] = ""
    end
    if type(record[field]) ~= "string" then
      return invalid(field)
    end
  end

  if record.timestamp == nil or record.timestamp == vim.NIL then
    record.timestamp = 0
  end
  if
    type(record.timestamp) ~= "number"
    or math.abs(record.timestamp) == math.huge
    or record.timestamp ~= math.floor(record.timestamp)
  then
    return invalid("timestamp")
  end

  if type(record.tags) ~= "table" or not vim.islist(record.tags) then
    return invalid("tags")
  end
  for _, tag in ipairs(record.tags) do
    if type(tag) ~= "string" then
      return invalid("tag")
    end
  end

  return record
end

--- Decode and validate one object emitted by the streaming JSON parser.
function M.decode_record(text, i, seen)
  local ok, record = pcall(vim.json.decode, text)
  if not ok then
    return nil, "Invalid search JSON: " .. tostring(record)
  end
  return M.validate_record(record, i, seen)
end

--- Decode a complete JSON array, keeping positional nulls intact.
function M.decode(text)
  local ok, records = pcall(vim.json.decode, text)
  if not ok then
    return nil, "Invalid search JSON: " .. tostring(records)
  end
  if type(records) ~= "table" or not vim.islist(records) or not text:match("^%s*%[") then
    return nil, "Search JSON must be an array"
  end
  local seen = {}
  for i, record in ipairs(records) do
    local valid, err = M.validate_record(record, i, seen)
    if not valid then
      return nil, err
    end
  end
  return records
end

return M
