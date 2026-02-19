" Syntax highlighting for notmuch-attachments buffer
" Oil.nvim-style: header + file paths as lines

if exists("b:current_syntax")
  finish
endif

" Header
syntax match NotmuchAttachHeader /^═.*═$/
highlight link NotmuchAttachHeader Title

" Hints line
syntax match NotmuchAttachHints /^Hints:.*/
highlight link NotmuchAttachHints Comment

" Separator
syntax match NotmuchAttachSeparator /^───.*$/
highlight link NotmuchAttachSeparator Comment

" File paths (lines after separator) - absolute paths
syntax match NotmuchAttachPath /^\/.*/
highlight link NotmuchAttachPath Directory

" File paths - relative paths (starting with ~/ or ./)
syntax match NotmuchAttachRelPath /^[~.]\/.*/
highlight link NotmuchAttachRelPath Directory

let b:current_syntax = "notmuch-attachments"
