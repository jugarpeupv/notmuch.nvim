let attach = v:lua.require('notmuch.attach')
nnoremap <buffer> q <Cmd>bwipeout<CR>
nnoremap <buffer> v <Cmd>call attach.view_attachment_part()<CR>
nnoremap <buffer> o <Cmd>call attach.open_attachment_part()<CR>
nnoremap <buffer> s <Cmd>lua require('notmuch.attach').save_attachment_part(nil, true)<CR>
