# vim-src
🦄 Minimalist Vim Script Loader


## Introduction
**vim-src** allows you to load Vim's configuration files via relative/absolute paths, which makes the modularization of vimrcs easier. It was inspired by the excellent Vim plugin manager [junegunn/vim-plug].

[junegunn/vim-plug]: https://github.com/junegunn/vim-plug


## Installation
[Download src.vim](https://raw.githubusercontent.com/JS-Zheng/vim-src/main/src.vim) and put it in the "autoload" directory.


## Usage
Add a **vim-src** section to your `~/.vimrc` (or `stdpath('config') . '/init.vim'` for Neovim)

1. Begin the section with `call src#begin([BASE_DIR])`
1. List the scripts with `Src` commands
1. `call src#end()` to end a vim-src section

### Example
```vim
call src#begin()
" The default base directory will be as follows:
"   - Vim (Linux/macOS): '~/.vim/vimrcs'
"   - Vim (Windows): '~/vimfiles/vimrcs'
"   - Neovim (Linux/macOS/Windows): stdpath('data') . '/vimrcs'
" You can specify a custom base directory by passing it as the argument
"   - e.g. `call src#begin('~/.my_vimrcs')`

" Use `Src!` to ensure only existing scripts will be loaded
Src! 'vimrc.pre'

" Use `Src` to load scripts
Src 'general.vim'
Src 'mappings.vim'
Src 'plugins.vim'
" Use an absolute path
Src '/Users/js-zheng/.vim/themes.vim'

Src! '~/.vimrc.post'

call src#end()
```
Reload .vimrc to load scripts.

### Nested Sections
vim-src supports **nested sections**, so in the *plugins.vim* (which loaded in the above example) can write:
```vim
call src#begin(expand('<sfile>:p:h') . '/plugin_configs')

" Equivalent to `source ~/.vim/vimrcs/plugin_configs/fzf.vim` in Vim (Unix)
Src 'fzf.vim'
Src 'fzf-grep.vim'
Src 'coc.vim'
Src 'fugitive.vim'
...

call src#end()

```


## Commands
| Command                      | Description                |
| ---------------------------- | ---------------------------|
| `Src [script path ...]`      | Load scripts               |
| `Src! [script path ...]`     | Load scripts with checking |

**NOTE:** `Src` command will load the current buffer if `script path` is empty.


## License
MIT

