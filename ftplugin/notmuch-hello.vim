" welcome screen displaying all tags available to search
let nm = v:lua.require('notmuch')
let r = v:lua.require('notmuch.refresh')
let s = v:lua.require('notmuch.sync')
nnoremap <buffer> <CR> <Cmd>call nm.search_terms("tag:" .. getline('.'))<CR>
nnoremap <buffer> c <Cmd>echo nm.count("tag:" .. getline('.'))<CR>
nnoremap <buffer> q <Cmd>bwipeout<CR>
nnoremap <buffer> r <Cmd>call r.refresh_hello_buffer()<CR>
nnoremap <buffer> C <Cmd>call v:lua.require('notmuch.send').compose()<CR>
nnoremap <buffer> % <Cmd>call s.sync_maildir()<CR>
