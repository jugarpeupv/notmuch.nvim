
if match(bufname("%"), "^thread:") != -1
	setlocal foldmethod=marker
	setlocal foldlevel=0

	" Make :e refresh the thread view instead of emptying this scratch
	" buffer (it is not a real file). Content is restored instantly from
	" the snapshot saved at write time (BufReadPre does NOT fire for
	" nofile buffers), then a real refresh runs deferred.
	autocmd BufReadCmd <buffer> call s:NotmuchThreadEditRefresh()
	function! s:NotmuchThreadEditRefresh() abort
	  " Renamed buffer or :e with a file argument: allow the normal edit.
	  if bufname('%') !~# '^thread:' || expand('<afile>') !=# bufname('%')
	    autocmd! * <buffer>
	    execute 'edit' fnameescape(expand('<afile>'))
	    return
	  endif
	  setlocal modifiable
	  if exists('b:notmuch_saved_thread_lines')
	    call setline(1, b:notmuch_saved_thread_lines)
	    if line('$') > len(b:notmuch_saved_thread_lines)
	      execute (len(b:notmuch_saved_thread_lines)+1) . ',$delete _'
	    endif
	  endif
	  setlocal nomodifiable
	  set nomodified
	  " :e clears buffer-local syntax items without refiring FileType, so
	  " force a reload (runtime syntax files bail out while
	  " b:current_syntax still exists).
	  if &l:syntax != ''
	    let l:syn = &l:syntax
	    unlet! b:current_syntax
	    setlocal syntax=
	    let &l:syntax = l:syn
	  endif
	  lua vim.schedule(function() require('notmuch.refresh').refresh_thread_buffer() end)
	endfunction

	command -buffer -complete=customlist,v:lua.require'notmuch.completion'.comp_tags -nargs=+ TagAdd :call v:lua.require('notmuch.tag').msg_add_tag("<args>")
	command -buffer -complete=customlist,v:lua.require'notmuch.completion'.comp_tags -nargs=+ TagRm :call tag.msg_rm_tag("<args>")
	command -buffer -complete=customlist,v:lua.require'notmuch.completion'.comp_tags -nargs=+ TagToggle :call tag.msg_toggle_tag("<args>")
	command -buffer FollowPatch :call v:lua.require('notmuch.attach').follow_github_patch(getline('.'))

	nnoremap <buffer> U <Cmd>call v:lua.require('notmuch.attach').get_urls_from_cursor_msg()<CR>
	nnoremap <buffer> <silent> <Tab>   <Cmd>call v:lua.require('notmuch.thread').next_message()<CR>
	nnoremap <buffer> <silent> <S-Tab> <Cmd>call v:lua.require('notmuch.thread').prev_message()<CR>
	nnoremap <buffer> <silent> <Enter> za
	nnoremap <buffer> a <Cmd>call v:lua.require('notmuch.attach').get_attachments_from_cursor_msg()<CR>
	nnoremap <buffer> r <Cmd>call v:lua.require('notmuch.refresh').refresh_thread_buffer()<CR>
	nnoremap <buffer> C <Cmd>call v:lua.require('notmuch.send').compose()<CR>
	nnoremap <buffer> R <Cmd>call v:lua.require('notmuch.send').reply()<CR>
	nnoremap <buffer> q <Cmd>bwipeout<CR>
	nnoremap <buffer> + :TagAdd<Space>
	nnoremap <buffer> - :TagRm<Space>
	nnoremap <buffer> = :TagToggle<Space>
endif
