setlocal conceallevel=3
setlocal concealcursor=

" ----------------------------------------------------------
" nmHints:
" First line always contains the Hints with key combinations
" ----------------------------------------------------------

syntax region nmHints		start=/^Hints:/ end=/$/		oneline	contains=nmHintsIdentifier
syntax match nmHintsIdentifier	"^Hints:"			contained nextgroup=nmHintsKey
syntax match nmHintsKey		"\s\+[^:\s]\+"			contained nextgroup=nmHintsKVDelimiter
syntax match nmHintsKVDelimiter	":"				contained nextgroup=nmHintsValue
syntax match nmHintsValue	"\s\+[A-Za-z0-9\ ,.]\+"		contained nextgroup=nmHintsDelimiter
syntax match nmHintsDelimiter	"|"				contained nextgroup=nmHintsKey

highlight link nmHintsIdentifier	Comment
highlight link nmHintsKey		Include
highlight link nmHintsKVDelimiter	Comment
highlight link nmHintsValue		Normal
highlight link nmHintsDelimiter		Comment

" ----------------------------------------------------------
" nmThreads:
" Color scheme for the rest of the buffer of threads
" ----------------------------------------------------------

syntax region nmThreads		start=/^thread/ end=/$/					oneline contains=nmThreadNum
syntax match nmThreadNum	"^thread"						contained nextgroup=nmThreadEllipsis conceal
syntax match nmThreadEllipsis	":"							contained nextgroup=nmThreadID conceal
syntax match nmThreadID		"[0-9a-z]\+"						contained nextgroup=nmDate conceal
syntax match nmDate		"\s\+[0-9A-Za-z.\-]\+\(\s[a-z0-9:.]\+\)\?\(\sago\)\?"	contained nextgroup=nmThreadCount
syntax match nmThreadCount	"\s\+\[[0-9]\+\/[0-9()]\+\]"				contained nextgroup=nmFrom
syntax match nmFrom		"\s\+.*;"						contained nextgroup=nmSubject
syntax match nmSubject		/.\{0,}\(([^()]\+)$\)\@=/				contained nextgroup=nmTags
syntax match nmTags		"(.*)$"							contained

" New display without thread: prefix (spaces) - robust fix for conceallevel
" Matches lines starting with spaces (thread: replaced with spaces) and highlights same as above
" Exclude aligned DD/MM/YY dates, 'thread:' and 'Hints:' so nmThreadLine,
" nmThreads and nmHints win for those lines
syntax match nmDatePlain		"^\s*\zs\%(\d\d\/\d\d\/\d\d \d\d:\d\d\|thread:\|Hints:\)\@![0-9A-Za-z.\-]\+\(\s[a-z0-9:.]\+\)\?\(\sago\)\?" nextgroup=nmThreadCountPlain
syntax match nmThreadCountPlain	"\s\+\[[0-9]\+\/[0-9()]\+\]"				contained nextgroup=nmFromPlain
syntax match nmFromPlain		"\s\+.*;"						contained nextgroup=nmSubjectPlain
syntax match nmSubjectPlain		".\{0,}\(([^()]\+)$\)\@="				contained nextgroup=nmTagsPlain
syntax match nmTagsPlain		"(.*)$"							contained
highlight link nmDatePlain String
highlight link nmThreadCountPlain Comment
highlight link nmFromPlain nmFrom
highlight link nmSubjectPlain Statement
highlight link nmTagsPlain Comment

highlight link nmThreadNum	Type
highlight link nmThreadEllipsis	Normal
highlight link nmThreadID	Include
highlight link nmDate		String
highlight link nmThreadCount	Comment
highlight nmFrom		ctermfg=224 guifg=Orange gui=italic
highlight link nmSubject	Statement
highlight link nmTags		Comment

" ----------------------------------------------------------
" nmThreadUnread / nmThreadRead:
" Aligned thread list produced by `notmuch search --format=json`:
" ICON DD/MM/YY HH:MM(14)  Subject(30)  From(10)  (tags)  [matched/total]
" The leading icon is U+F01EE (closed envelope) for threads tagged `unread`
" and U+F01EF (opened envelope) otherwise; each state has its own region so
" the icon gets its own color via matchgroup (NotmuchUnreadMail/ReadMail).
" A region + nextgroup chain is used on purpose: after a match Vim resumes
" scanning after it, so a second `^`-anchored pattern on the same line can
" never match again. Separators are part of each pattern instead.
" Subject/From use lazy matches pinned to the end-of-line tags + count
" (instead of fixed `.\{N}` widths): wide chars such as emoji or CJK make
" character count differ from display width, which would otherwise shift
" every field after them. The EOL anchor keeps exactly one valid parse.
" ----------------------------------------------------------

syntax region nmThreadUnread	matchgroup=nmUnreadIcon start=/^\%U000F01EE/ end=/$/	oneline contains=nmDateA
syntax region nmThreadRead	matchgroup=nmReadIcon start=/^\%U000F01EF/ end=/$/	oneline contains=nmDateA
syntax match nmDateA		/\s\+\d\d\/\d\d\/\d\d \d\d:\d\d/	contained nextgroup=nmSubjectA
syntax match nmSubjectA		/\s\{2\}.\{-\}\ze\s\{2\}.\{10}\s\{2\}([^()]*)\s\+\[\d\+\/\d\+\]$/	contained nextgroup=nmFromA
syntax match nmFromA		/\s\{2\}.\{-\}\ze\s\{2\}([^()]*)\s\+\[\d\+\/\d\+\]$/			contained nextgroup=nmTagsA
syntax match nmTagsA		/\s\+([^()]*)/				contained nextgroup=nmThreadCountA
syntax match nmThreadCountA	/\s\+\[\d\+\/\d\+\]/			contained

highlight default NotmuchUnreadMail	ctermfg=214 guifg=#fabd2f gui=bold
highlight default NotmuchReadMail	ctermfg=244 guifg=#8a8a8a
highlight link nmUnreadIcon	NotmuchUnreadMail
highlight link nmReadIcon	NotmuchReadMail
highlight link nmDateA		String
highlight link nmSubjectA	Statement
highlight link nmFromA		nmFrom
highlight link nmTagsA		Comment
highlight link nmThreadCountA	Comment
