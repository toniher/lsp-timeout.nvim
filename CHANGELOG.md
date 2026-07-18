# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [semver](https://semver.org/). Entries before 1.3.0 were not
tracked in this file — see the `vX.Y.Z` git tags for that history.

## [1.3.0]

### Added

- `:checkhealth lsp-timeout`, reporting LSP command availability
  (`vim.lsp.enable`/`nvim-lspconfig`), config validity, paused state, and
  `stopTimer`/`startTimer` status.
- `:LspTimeoutPause` / `:LspTimeoutResume`, to temporarily disable
  focus-triggered stop/restart without editing `vim.g.lspTimeoutConfig`.
  Pausing doesn't cancel an already-armed timer; a pending stop/restart still
  fires once.
- `:LspTimeoutStatus`, a one-line `vim.notify` summary of paused state, timer
  status, and stopped-client count — a quicker alternative to
  `:checkhealth` for a fast glance.
- Support for Neovim 0.12+'s built-in LSP client management
  (`vim.lsp.enable`, `vim.lsp.get_configs`, `vim.lsp.get_clients`) alongside
  the existing `nvim-lspconfig` backend, auto-detected at `VimEnter`.
- Test suite: `tests/tests_spec.lua` (Config class) via a plenary/busted
  harness, plus CI workflow and per-version Makefiles; `tests/plugin_spec.lua`
  adds mock-based coverage of the `FocusGained`/`FocusLost` autocmd handlers
  (timer arming/firing, per-buffer client matching, pause no-op, ignored
  filetypes) — previously the highest-risk, untested part of the plugin.

### Fixed

- `FocusLost` now records each tab buffer's own stopped LSP clients under its
  own key, instead of lumping every buffer's clients under a single trigger
  buffer; `FocusGained` can now restart every buffer exactly, not just the
  last-focused one.
- `FocusGained`/`FocusLost` crashing on real Neovim v0.7.2 (`invalid key:
  buf`/`invalid key: win`) — `nvim-api.lua`'s `Buffer:option`/`Window:option`
  assumed `nvim_get_option_value`'s mere existence meant it accepted the
  scoped `{buf=...}`/`{win=...}` opts, which isn't true on v0.7.2; now falls
  back to the older buf/win-scoped option API via `pcall` detection.
- `vim.tbl_islist`/`vim.tbl_isarray` deprecation warnings on newer Neovim,
  replaced with `vim.islist` (closes #17).
- Dead/overlapping `filetypes` validation block in `config.lua`'s
  `validate()`, and a no-op `:format()` call (no placeholder) in the
  `FocusLost` notify message.
- `BufEnter` handler read the global `vim.bo.filetype` instead of the
  buffer-scoped `vim.bo[bufnr].filetype`; `lsp-timeout.config` failing to
  load is now handled defensively instead of erroring the autocmd.
- CI not running the full test suite by default (missing `.DEFAULT_GOAL`
  and an explicit `all` target in `tests/Makefile`).

### Docs

- `doc/lsp-timeout.txt` (the generated `:help lsp-timeout` file) updated by
  hand to cover the new Commands section and `:checkhealth` mention —
  `ts-vimdoc.nvim` isn't available in this environment to regenerate it from
  `doc/index.md` automatically.
- `README.md`/`doc/index.md` no longer describe `nvim-lspconfig` as a hard
  requirement; it's optional on Neovim 0.12+, which uses the built-in
  `vim.lsp.enable`/`vim.lsp.get_configs` instead.
- Bug issue template now asks for `:checkhealth lsp-timeout` output.

### Internal

- PR template previously pointed contributions at the `dev` branch; the
  `dev` and `initial` branches have since been removed from this fork, so
  the redirect was dropped and the CI workflow (`.github/workflows/tests.yml`)
  now triggers on `main` only (renamed from `dev` to `tests`).
