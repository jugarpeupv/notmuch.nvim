# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-01-09

### Added

- Sort toggle (`o` keymap) in thread results buffer to reverse search order (newest-first ↔ oldest-first)
- Exit code detection and auto-close terminal on successful email send
- In-buffer attachment viewer for text-based files (text, markdown, PDFs)
- Dedicated `handlers.lua` module with comprehensive file type support for attachments
  - OS-aware external opening (macOS, Linux, Windows)
  - Graceful fallbacks for HTML, PDF, images, Office documents, markdown, and archives
- Interactive save prompt for attachments with validation
  - Directory validation and writability checks
  - Overwrite confirmation
  - Path expansion support (~, environment variables)
- Hints line in `notmuch-attach` buffers with syntax highlighting
- Attachment support for composing mail via `<C-g><C-a>` keymap
- Attachment support for replies using command-based interface
  - `:Attach`, `:AttachList`, `:AttachRemove` commands with tab completion
- MIME message builder for multipart emails with attachments
- Improved msmtp logging and multi-account support
  - `logfile` config option for msmtp
  - `--read-envelope-from` flag for multiple sending accounts
- Delete functionality for threads
  - `:DelThread` command (bound to `dd` in normal mode, `d` in visual mode)
  - `D` key to preview deletion, `DD` to confirm purge
- Enhanced search term autocompletion
  - Added `is:`, `to:`, `from:`, `body:`, and logical expressions (`and`, `or`, `not`)
  - Autocomplete for `mimetype:`, `to:`, `from:`, `path:`, and `folder:` search
- `:ComposeMail` now accepts optional recipient with autocomplete
- Visual mode support for tag operations (`+`, `-`, `=`, `a`, `A`, `x`) in threads view
- `f` key binding to toggle `flagged` tag in threads view (normal and visual mode)
- Fail-fast validation for notmuch configuration on plugin load
- Hint in compose message body showing attachment window keymap

### Changed

- **BREAKING**: Renamed `open_cmd` config option to `open_handler` (now a callback function)
- Send email now uses terminal buffer instead of background process
- Path expansion for user-override `notmuch_db_path` config (handles `~` and relative paths)
- Attachment listing now uses JSON parsing instead of grep for reliability
  - Recursive MIME tree parsing
  - Accurate part IDs, filenames, sizes, and disposition indicators
- Sync operation improvements
  - Now runs asynchronously
  - Displays sync command and user-friendly status text
  - Statusline notifications on success/failure
  - `<C-c>` cancellation only works when sync is running
- Tag command mappings now include trailing space for better UX
- Single-part MIME for plaintext emails without attachments
- Optimized bulk thread tagging by reusing database connection (reduces N connections to 1)
- Sync mode configuration now uses `sync.sync_mode` structure

### Fixed

- Buffer write notifications silenced during email composition
- Removed duplicate `s` keymap for saving attachment parts
- Visual mode mappings reverted to `:` prefix instead of `<Cmd>`
- Keymap definitions now use `<Cmd>` for better reliability
- Cross-platform tempfile creation using `vim.fn.tempname()` instead of `mktemp`
- Message ID sanitization for reply filenames (prevents invalid file paths)
- View attachment floating buffer now properly unlisted
- Last-ditch fallback added when filetype not supported in view handler
- Attachment handling now uses `vim.split` instead of custom string splitting
- Shell-escaped naming for attachment paths
- Sync cancellation keymap race condition
- UI sync export issue
- Tag operations now use `nnoremap` instead of `nmap` to prevent conflicts
- Compose buffer content retained if attachment validation fails
- Attachment validation now checks for existence and accessibility
- Body content no longer parsed as email headers (RFC 5322 compliance)
  - Added support for header continuation (folded headers)
- Empty lines in attachment buffer no longer cause errors
- MIME module function naming issues
- Cross-platform folder/path autocomplete with special character support
  - Removed BSD-incompatible `sed -z`
  - Added shell injection protection
  - Auto-quotes paths with spaces or brackets

### Security

- Fixed command injection vulnerability in `sendmail()` function
  - Replaced string concatenation with proper argument escaping
  - Now uses `vim.fn.system()` with array arguments

## [0.1.0] - 2025-01-18

Initial (informal) baseline release.

[Unreleased]: https://github.com/yousefakbar/notmuch.nvim/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/yousefakbar/notmuch.nvim/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/yousefakbar/notmuch.nvim/commit/e4b0a6cbbe5e5281f7a6a8fa43c3e776d3eaec64
