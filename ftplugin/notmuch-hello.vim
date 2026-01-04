" welcome screen displaying all tags available to search
let nm = v:lua.require('notmuch')
let r = v:lua.require('notmuch.refresh')
let s = v:lua.require('notmuch.sync')
nnoremap <buffer> <silent> <CR> <Cmd>call nm.search_terms("tag:" .. getline('.'))<CR>
nnoremap <buffer> <silent> c <Cmd>echo nm.count("tag:" .. getline('.'))<CR>
nnoremap <buffer> <silent> q <Cmd>bwipeout<CR>
nnoremap <buffer> <silent> r <Cmd>call r.refresh_hello_buffer()<CR>
nnoremap <buffer> <silent> C <Cmd>call v:lua.require('notmuch.send').compose()<CR>
nnoremap <buffer> <silent> % <Cmd>call s.sync_maildir()<CR>
