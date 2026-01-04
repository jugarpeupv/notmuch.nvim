setlocal nowrap

let nm = v:lua.require('notmuch')
let r = v:lua.require('notmuch.refresh')
let s = v:lua.require('notmuch.sync')
let tag = v:lua.require('notmuch.tag')

command -buffer -range -complete=custom,notmuch#CompTags -nargs=+ TagAdd :call tag.thread_add_tag(<q-args>, <line1>, <line2>)
command -buffer -range -complete=custom,notmuch#CompTags -nargs=+ TagRm :call tag.thread_rm_tag(<q-args>, <line1>, <line2>)
command -buffer -range -complete=custom,notmuch#CompTags -nargs=+ TagToggle :call tag.thread_toggle_tag(<q-args>, <line1>, <line2>)
command -buffer -range DelThread :call tag.thread_add_tag("del", <line1>, <line2>) | :call tag.thread_rm_tag("inbox", <line1>, <line2>)

nnoremap <buffer> <silent> <CR> <Cmd>call nm.show_thread()<CR>
nnoremap <buffer> <silent> r <Cmd>call r.refresh_search_buffer()<CR>
nnoremap <buffer> <silent> q <Cmd>bwipeout<CR>
nnoremap <buffer> <silent> % <Cmd>call s.sync_maildir()<CR>
nnoremap <buffer> + :TagAdd
xnoremap <buffer> + :TagAdd
nnoremap <buffer> - :TagRm
xnoremap <buffer> - :TagRm
nnoremap <buffer> = :TagToggle
xnoremap <buffer> = :TagToggle
nnoremap <buffer> a <Cmd>TagToggle inbox<CR>j
xnoremap <buffer> a <Cmd>TagToggle inbox<CR>
nnoremap <buffer> A <Cmd>TagRm inbox unread<CR>j
xnoremap <buffer> A <Cmd>TagRm inbox unread<CR>
nnoremap <buffer> x <Cmd>TagToggle unread<CR>
xnoremap <buffer> x <Cmd>TagToggle unread<CR>
nnoremap <buffer> f <Cmd>TagToggle flagged<CR>j
xnoremap <buffer> f <Cmd>TagToggle flagged<CR>
nnoremap <buffer> <silent> C <Cmd>call v:lua.require('notmuch.send').compose()<CR>
nnoremap <buffer> dd <Cmd>DelThread<CR>j
xnoremap <buffer> d <Cmd>DelThread<CR>
nnoremap <buffer> <silent> D <Cmd>lua require('notmuch.delete').purge_del()<CR>
