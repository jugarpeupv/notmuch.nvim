local t = {}
local v = vim.api
local thread = require('notmuch.thread')
local u = require'notmuch.util'

local config = require('notmuch.config')

t.msg_add_tag = function(tags)
  local t = u.split(tags, '%S+')
  local db = require'notmuch.cnotmuch'(config.options.notmuch_db_path, 1)
  local id = thread.get_current_message_id()
  if id == nil then return end
  local msg = db.get_message(id)
  for i,tag in pairs(t) do
    msg:add_tag(tag)
  end
  db.close()
  print('+(' .. tags .. ')')
end

t.msg_rm_tag = function(tags)
  local t = u.split(tags, '%S+')
  local db = require'notmuch.cnotmuch'(config.options.notmuch_db_path, 1)
  local id = thread.get_current_message_id()
  if id == nil then return end
  local msg = db.get_message(id)
  for i,tag in pairs(t) do
    msg:rm_tag(tag)
  end
  db.close()
  print('-(' .. tags .. ')')
end

t.msg_toggle_tag = function(tags)
  local t = u.split(tags, '%S+')
  local db = require'notmuch.cnotmuch'(config.options.notmuch_db_path, 1)
  local id = thread.get_current_message_id()
  if id == nil then return end
  local msg = db.get_message(id)
  local curr_tags = msg:get_tags()
  for i,tag in pairs(t) do
    if curr_tags[tag] == true then
      msg:rm_tag(tag)
      print('-' .. tag)
    else
      msg:add_tag(tag)
      print('+' .. tag)
    end
  end
  db.close()
end

local function get_thread_id_for_lnum(buf, lnum)
  if lnum <= 2 then return nil end
  local ids = vim.b[buf] and vim.b[buf].notmuch_thread_ids
  if ids and ids[lnum - 2] then return ids[lnum - 2] end
  local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or vim.fn.getline(lnum)
  if line:find("Hints:") == 1 then return nil end
  return string.match(line, "[0-9a-fA-F]+", 7) or string.match(line, "%S+", 8)
end

t.thread_add_tag = function(tags, startlinenr, endlinenr)
  local buf = vim.api.nvim_get_current_buf()
  startlinenr = startlinenr or v.nvim_win_get_cursor(0)[1]
  endlinenr = endlinenr or startlinenr
  local t = u.split(tags, '%S+')
  local db = require("notmuch.cnotmuch")(config.options.notmuch_db_path, 1)
  for linenr = startlinenr, endlinenr do
    local threadid = get_thread_id_for_lnum(buf, linenr)
    if threadid and threadid ~= "" then
      local query = db.create_query("thread:" .. threadid)
      local thread = query.get_threads()[1]
      if thread then
        for i,tag in pairs(t) do
          thread:add_tag(tag)
        end
      end
    else
      vim.notify("thread_add_tag: could not get thread ID for line " .. linenr, vim.log.levels.WARN)
    end
  end
  db.close()
  print('+(' .. tags .. ')')
end

t.thread_rm_tag = function(tags, startlinenr, endlinenr)
  local buf = vim.api.nvim_get_current_buf()
  startlinenr = startlinenr or v.nvim_win_get_cursor(0)[1]
  endlinenr = endlinenr or startlinenr
  local t = u.split(tags, '%S+')
  local db = require("notmuch.cnotmuch")(config.options.notmuch_db_path, 1)
  for linenr = startlinenr, endlinenr do
    local threadid = get_thread_id_for_lnum(buf, linenr)
    if threadid and threadid ~= "" then
      local query = db.create_query("thread:" .. threadid)
      local thread = query.get_threads()[1]
      if thread then
        for i,tag in pairs(t) do
          thread:rm_tag(tag)
        end
      end
    else
      vim.notify("thread_rm_tag: could not get thread ID for line " .. linenr, vim.log.levels.WARN)
    end
  end
  db.close()
  print('-(' .. tags .. ')')
end

t.thread_toggle_tag = function(tags, startlinenr, endlinenr)
  local buf = vim.api.nvim_get_current_buf()
  startlinenr = startlinenr or v.nvim_win_get_cursor(0)[1]
  endlinenr = endlinenr or startlinenr
  local t = u.split(tags, '%S+')
  local db = require("notmuch.cnotmuch")(config.options.notmuch_db_path, 1)
  for linenr = startlinenr, endlinenr do
    local threadid = get_thread_id_for_lnum(buf, linenr)
    if threadid and threadid ~= "" then
      local query = db.create_query("thread:" .. threadid)
      local thread = query.get_threads()[1]
      if thread then
        local curr_tags = thread:get_tags()
        for i,tag in pairs(t) do
          if curr_tags[tag] == true then
            thread:rm_tag(tag)
            print("-" .. tag)
          else
            thread:add_tag(tag)
            print("+" .. tag)
          end
        end
      end
    else
      vim.notify("thread_toggle_tag: could not get thread ID for line " .. linenr, vim.log.levels.WARN)
    end
  end
  db.close()
end

return t

-- vim: tabstop=2:shiftwidth=2:expandtab:foldmethod=indent
