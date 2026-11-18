-- notmuch-attachments: oil.nvim-style draft attachment buffer.
--
-- Migrated from ftplugin/notmuch-attachments.vim. This buffer is editable;
-- keymaps are installed by lua/notmuch/attach_buffer.lua.

if vim.b.did_ftplugin then
  return
end
vim.b.did_ftplugin = 1

-- Buffer settings - NOTE: buffer IS modifiable (oil.nvim style).
vim.opt_local.buftype = "acwrite"
vim.opt_local.bufhidden = "hide"
vim.opt_local.swapfile = false
vim.opt_local.wrap = false
vim.opt_local.cursorline = true

-- Disable some common plugins that might interfere.
vim.b.loaded_coc = 1
vim.b.coc_enabled = 0
vim.b.copilot_enabled = 0
