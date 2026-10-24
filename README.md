# vim-src

A minimalist Vim and Neovim config loader.

---

## Overview

`vim-src` helps you organize your Vim / Neovim configuration into small,
composable files and load them in a predictable way.

Supported editors:

* Vim 8.2+
* Neovim 0.4.4+

It is intentionally minimal.

`vim-src` is **not** a plugin manager.  
It does not modify `runtimepath` or manage packages.

It resolves a base directory and loads configuration files relative to it.

---

## Philosophy

- Minimal surface area
- Deterministic behavior
- Explicit over implicit
- No runtimepath magic

`vim-src` is designed for early startup and bootstrap usage.

---

## Installation

Recommended: copy `autoload/src.vim` into your config early:

```text
~/.vim/autoload/src.vim
```

or for Neovim:

```text
~/.config/nvim/autoload/src.vim
```

This keeps `vim-src` available as early as possible during startup.

You can also install it with [vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'JS-Zheng/vim-src'
```

Requirements:

* Vim 8.2+ or Neovim 0.4.4+

---

## Quick Start

```vim
call src#init()

Src 'general.vim'
Src 'mappings.vim'
Src 'plugins'
```

If your base directory is:

```text
~/.vim/vimrcs/
```

Then:

```vim
Src 'general.vim'
```

loads:

```text
~/.vim/vimrcs/general.vim
```

Typical setup:

```vim
call src#init()

let g:src.base_name = 'vimrcs'
Src 'general.vim'
Src! '~/.local.vimrc'

call src#begin('plugins')
Src 'git.vim'
Src 'fzf.vim'
call src#end()

call src#begin('theme')
Src 'colorscheme.vim'
Src 'statusline.vim'
call src#end()
```

---

## Directory Loading

If the target is a directory:

```vim
Src 'plugins'
```

All direct child `*.vim` files are sourced in lexical order:

```text
plugins/
  10-core.vim
  20-git.vim
  30-fzf.vim
```

Rules:

* non-recursive
* only direct children
* only `*.vim`
* hidden files ignored
* explicit symlinked files and directories are resolved and loaded
* symlinked `*.vim` children are loaded; directory children remain non-recursive

---

## Common Usage

Interactive command usage:

```vim
:Src
:Src 'general.vim'
:Src 'plugins'
```

This is especially handy while developing Vimscript:

- `:Src` reloads the current buffer
- `:Src 'file.vim'` reloads one file
- `:Src 'plugins'` reloads a small config directory

Optional local file:

```vim
Src! '~/.local.vimrc'
```

Temporary nested scope:

```vim
call src#begin('plugins')
Src 'git.vim'
Src 'fzf.vim'
call src#end()

call src#begin('theme')
Src 'colorscheme.vim'
Src 'statusline.vim'
call src#end()
```

Directory loading from the command line:

```vim
:Src 'plugins'
```

This loads direct child `*.vim` files from that directory in lexical order.

Example:

```text
plugins/
  10-core.vim
  20-git.vim
  30-fzf.vim
```

Running:

```vim
:Src 'plugins'
```

loads:

1. `10-core.vim`
2. `20-git.vim`
3. `30-fzf.vim`

Common options:

```vim
let g:src.base_dir = '~/.vim/vimrcs'
let g:src.base_name = 'vimrcs'
```

Symlinks are always followed. The former `follow_links` option is no longer
supported.

---

## Scope

Use `vim-src` for:

* personal config organization
* modular configuration trees
* local overrides

Not for:

* plugin management
* package management
* runtimepath manipulation

---

## More

For full usage, options, and help tags, see:

- `:help vim-src`
- [doc/vim-src.txt](doc/vim-src.txt)

---

## License

See [LICENSE](LICENSE).
