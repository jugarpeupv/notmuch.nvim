let attach = v:lua.require('notmuch.attach')
nnoremap <buffer> <silent> q <Cmd>bwipeout<CR>
nnoremap <buffer> <silent> s <Cmd>call attach.save_attachment_part()<CR>
nnoremap <buffer> <silent> v <Cmd>call attach.view_attachment_part()<CR>
nnoremap <buffer> <silent> o <Cmd>call attach.open_attachment_part()<CR>
nnoremap <buffer> s <Cmd>lua require('notmuch.attach').save_attachment_part(nil, true)<CR>
