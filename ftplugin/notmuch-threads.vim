setlocal nowrap

let nm = v:lua.require('notmuch')
let r = v:lua.require('notmuch.refresh')
let s = v:lua.require('notmuch.sync')
let tag = v:lua.require('notmuch.tag')

command -buffer -range -complete=custom,notmuch#CompTags -nargs=+ TagAdd :call tag.thread_add_tag(<q-args>, <line1>, <line2>)
command -buffer -range -complete=custom,notmuch#CompTags -nargs=+ TagRm :call tag.thread_rm_tag(<q-args>, <line1>, <line2>)
command -buffer -range -complete=custom,notmuch#CompTags -nargs=+ TagToggle :call tag.thread_toggle_tag(<q-args>, <line1>, <line2>)
command -buffer -range DelThread :call tag.thread_add_tag("del", <line1>, <line2>) | :call tag.thread_rm_tag("inbox", <line1>, <line2>)

nnoremap <buffer> <CR> <Cmd>call nm.show_thread()<CR>
nnoremap <buffer> r <Cmd>call r.refresh_search_buffer()<CR>
nnoremap <buffer> q <Cmd>bwipeout<CR>
nnoremap <buffer> % <Cmd>call s.sync_maildir()<CR>
nnoremap <buffer> + :TagAdd<Space>
xnoremap <buffer> + :TagAdd<Space>
nnoremap <buffer> - :TagRm<Space>
xnoremap <buffer> - :TagRm<Space>
nnoremap <buffer> = :TagToggle<Space>
xnoremap <buffer> = :TagToggle<Space>
nnoremap <buffer> a <Cmd>TagToggle inbox<CR>j
xnoremap <buffer> a :TagToggle inbox<CR>
nnoremap <buffer> A <Cmd>TagRm inbox unread<CR>j
xnoremap <buffer> A :TagRm inbox unread<CR>
nnoremap <buffer> x <Cmd>TagToggle unread<CR>
xnoremap <buffer> x :TagToggle unread<CR>
nnoremap <buffer> f <Cmd>TagToggle flagged<CR>j
xnoremap <buffer> f :TagToggle flagged<CR>
nnoremap <buffer> C <Cmd>call v:lua.require('notmuch.send').compose()<CR>
nnoremap <buffer> dd <Cmd>DelThread<CR>j
xnoremap <buffer> d :DelThread<CR>
nnoremap <buffer> D <Cmd>lua require('notmuch.delete').purge_del()<CR>
nnoremap <buffer> o <Cmd>call nm.reverse_sort_threads()<CR>
