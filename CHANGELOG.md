# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Removed

- **Breaking:** the `follow_links` option is gone from `g:src`, from `:Src`
  options, and as the second argument of `src#begin()`. Symlinks are always
  followed.

### Changed

- **Breaking:** boolean options (`g:src.def_commands`, `g:src.debug`, the
  `optional` argument, and the `optional` and `if` command options) accept only
  Number, Float, or Boolean values. Strings and containers are rejected.
- **Breaking:** an empty target or `src#begin('')` is rejected with
  `invalid argument`. With `!`, an empty target is skipped, so an unset variable
  in `Src! $LOCAL_VIMRC` no longer loads the whole base directory.
- The default base directory is resolved on every use instead of being cached.
- Scopes still open when startup ends are closed at `VimEnter` with a warning,
  so a vimrc aborted by an error no longer leaves later `:Src` calls in a stale
  scope.

### Fixed

- Directory targets on Neovim before 0.5, which lacks `readdir()`.
- `:Src` on `$MYVIMRC` resolving relative targets next to the vimrc instead of
  from the startup base directory, including on Windows with mixed separators.
- `:Src` on a modified Lua buffer in Neovim sourcing it as Vimscript.
- A collision warning for vim-src's own `:Src` after re-sourcing
  `autoload/src.vim`, or when a buffer-local `:Src` exists.
- An `E684` error that hid the real failure when `autoload/src.vim` was
  re-sourced while sourcing.

### Documentation

- How relative targets resolve inside loaded files, the limits of `:Src`
  argument evaluation, and how errors propagate.
- Plugin managers make vim-src available only after they finish loading.

## [0.1.0] - 2026-04-23

- Initial release.

[Unreleased]: https://github.com/JS-Zheng/vim-src/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/JS-Zheng/vim-src/releases/tag/v0.1.0
