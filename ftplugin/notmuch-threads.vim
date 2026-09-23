setlocal nowrap
setlocal conceallevel=3
setlocal concealcursor=
setlocal signcolumn=no
" Make :e behave like r (refresh) in this scratch buffer (not a real file)
" Save state before :e clears the buffer, restore it in BufReadCmd so there
" is no empty flash, then schedule a real refresh (deferred to avoid
" re-entrancy: refresh does bwipeout + re-search).
autocmd BufReadPre <buffer> if line('$') > 1 || getline(1) != '' | let b:notmuch_saved_lines = getline(1, '$') | let b:notmuch_saved_ids = get(b:, 'notmuch_thread_ids', []) | let b:notmuch_saved_lnum = line('.') | endif
autocmd BufReadCmd <buffer> call s:NotmuchEditRefresh()
function! s:NotmuchEditRefresh() abort
  " :e with a file argument: allow the normal edit, drop our guard
  if expand('<afile>') !=# bufname('%')
    autocmd! * <buffer>
    execute 'edit' fnameescape(expand('<afile>'))
    return
  endif
  setlocal modifiable
  if exists('b:notmuch_saved_lines')
    call setline(1, b:notmuch_saved_lines)
    if line('$') > len(b:notmuch_saved_lines)
      execute (len(b:notmuch_saved_lines)+1) . ',$delete _'
    endif
    if exists('b:notmuch_saved_ids') | let b:notmuch_thread_ids = b:notmuch_saved_ids | endif
    if exists('b:notmuch_saved_lnum') | call cursor(b:notmuch_saved_lnum, 1) | endif
  endif
  setlocal nomodifiable
  set nomodified
  lua vim.schedule(function() require('notmuch.refresh').refresh_search_buffer() end)
endfunction

let nm = v:lua.require('notmuch')
let r = v:lua.require('notmuch.refresh')
let s = v:lua.require('notmuch.sync')
let tag = v:lua.require('notmuch.tag')

command -buffer -range -complete=customlist,v:lua.require'notmuch.completion'.comp_tags -nargs=+ TagAdd :call tag.thread_add_tag(<q-args>, <line1>, <line2>)
command -buffer -range -complete=customlist,v:lua.require'notmuch.completion'.comp_tags -nargs=+ TagRm :call tag.thread_rm_tag(<q-args>, <line1>, <line2>)
command -buffer -range -complete=customlist,v:lua.require'notmuch.completion'.comp_tags -nargs=+ TagToggle :call tag.thread_toggle_tag(<q-args>, <line1>, <line2>)
command -buffer -range DelThread :call tag.thread_add_tag("del", <line1>, <line2>) | :call tag.thread_rm_tag("inbox", <line1>, <line2>)

nnoremap <buffer> <CR> <Cmd>call nm.show_thread()<CR>
nnoremap <buffer> <C-v> <Cmd>lua require('notmuch').show_thread_vsplit()<CR>
nnoremap <buffer> <C-s> <Cmd>lua require('notmuch').show_thread_split()<CR>
nnoremap <buffer> <C-x> <Cmd>lua require('notmuch').show_thread_split()<CR>
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
