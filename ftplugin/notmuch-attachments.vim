" ftplugin for notmuch-attachments buffers
" This buffer works like oil.nvim: each line after the header is a file path.
" - Use dd to delete an attachment
" - Paste file paths with p (e.g. from oil.nvim)
" - Use a/b/t for add/browse/telescope

if exists("b:did_ftplugin")
  finish
endif
let b:did_ftplugin = 1

" Buffer settings - NOTE: buffer IS modifiable (oil.nvim style)
setlocal buftype=acwrite
setlocal bufhidden=hide
setlocal noswapfile
setlocal nowrap
setlocal cursorline

" Disable some common plugins that might interfere
let b:loaded_coc = 1
let b:coc_enabled = 0
let b:copilot_enabled = 0

" Keybindings are set in the Lua module (attach_buffer.lua)
