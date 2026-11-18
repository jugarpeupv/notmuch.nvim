-- notmuch-hello: landing page listing all tags.
--
-- Migrated from ftplugin/notmuch-hello.vim.

if vim.b.did_ftplugin then
  return
end
vim.b.did_ftplugin = 1

local nm = require("notmuch")
local r = require("notmuch.refresh")
local s = require("notmuch.sync")

local function map(lhs, rhs, opts)
  opts = vim.tbl_extend("force", { buffer = true }, opts or {})
  vim.keymap.set("n", lhs, rhs, opts)
end

map("<CR>", function()
  nm.search_terms("tag:" .. vim.api.nvim_get_current_line())
end)
map("c", function()
  print(nm.count("tag:" .. vim.api.nvim_get_current_line()))
end)
map("q", "<Cmd>bwipeout<CR>")
map("r", r.refresh_hello_buffer)
map("C", function()
  require("notmuch.send").compose()
end)
map("%", s.sync_maildir)
