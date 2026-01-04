
if match(bufname("%"), "^thread:") != -1
	setlocal foldmethod=marker
	setlocal foldlevel=0

	command -buffer -complete=custom,notmuch#CompTags -nargs=+ TagAdd :call v:lua.require('notmuch.tag').msg_add_tag("<args>")
	command -buffer -complete=custom,notmuch#CompTags -nargs=+ TagRm :call tag.msg_rm_tag("<args>")
	command -buffer -complete=custom,notmuch#CompTags -nargs=+ TagToggle :call tag.msg_toggle_tag("<args>")
	command -buffer FollowPatch :call v:lua.require('notmuch.attach').follow_github_patch(getline('.'))

	nnoremap <buffer> U <Cmd>call v:lua.require('notmuch.attach').get_urls_from_cursor_msg()<CR>
	nnoremap <buffer> <silent> <Tab> zj
	nnoremap <buffer> <silent> <S-Tab> zk
	nnoremap <buffer> <silent> <Enter> za
	nnoremap <buffer> a <Cmd>call v:lua.require('notmuch.attach').get_attachments_from_cursor_msg()<CR>
	nnoremap <buffer> r <Cmd>call v:lua.require('notmuch.refresh').refresh_thread_buffer()<CR>
	nnoremap <buffer> C <Cmd>call v:lua.require('notmuch.send').compose()<CR>
	nnoremap <buffer> R <Cmd>call v:lua.require('notmuch.send').reply()<CR>
	nnoremap <buffer> q <Cmd>bwipeout<CR>
	nnoremap <buffer> + :TagAdd
	nnoremap <buffer> - :TagRm
	nnoremap <buffer> = :TagToggle
endif
