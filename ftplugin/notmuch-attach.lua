-- notmuch-attach: attachment listing buffer.
--
-- Migrated from ftplugin/notmuch-attach.vim.

if vim.b.did_ftplugin then
  return
end
vim.b.did_ftplugin = 1

local attach = require("notmuch.attach")

local function map(lhs, rhs)
  vim.keymap.set("n", lhs, rhs, { buffer = true })
end

map("q", "<Cmd>bwipeout<CR>")
map("v", function()
  attach.view_attachment_part()
end)
map("o", function()
  attach.open_attachment_part()
end)
map("s", function()
  attach.save_attachment_part(nil, true)
end)
