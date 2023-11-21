# vim-src
🦄 Minimalist Vim Script Loader


## Introduction
**vim-src** simplifies the process of loading Vim's configuration files from relative or absolute paths. This enhancement aids in the modularization of `.vimrc` files. Inspired by the excellent [junegunn/vim-plug] Vim plugin manager.

[junegunn/vim-plug]: https://github.com/junegunn/vim-plug


## Installation
To install, [download src.vim](https://raw.githubusercontent.com/JS-Zheng/vim-src/main/autoload/src.vim) and place it in the "autoload" directory of your Vim or Neovim setup.


## Usage
Incorporate a **vim-src** section in your `~/.vimrc` (or `stdpath('config') . '/init.vim'` for Neovim) as follows:

1. Start the section with `call src#begin([BASE_DIR])`.
2. List the scripts using `Src` commands.
3. Conclude with `call src#end()`.

### Example
```vim
call src#begin()
" By default, the base directory is set as:
"   - Vim (Linux/macOS): '~/.vim/vimrcs'
"   - Vim (Windows): '~/vimfiles/vimrcs'
"   - Neovim (Linux/macOS/Windows): stdpath('data') . '/vimrcs'
" For a custom base directory, pass it as an argument,
"   - e.g. `call src#begin('~/.my_vimrcs')`

" Use `Src!` to load only existing scripts
Src! 'vimrc.pre'

" Regular `Src` command for loading scripts
Src 'general.vim'
Src 'mappings.vim'
Src 'plugins.vim'

" Loading scripts using an absolute path
Src '/Users/js-zheng/.vim/themes.vim'

Src! '~/.vimrc.post'

call src#end()
```
Reload your .vimrc to apply the changes.

### Nested Sections
**vim-src** also supports **nested sections**. For example, within plugins.vim (as loaded above), you could write:
```vim
call src#begin(expand('<sfile>:p:h') . '/plugin_configs')

" This is equivalent to `source ~/.vim/vimrcs/plugin_configs/fzf.vim` in Vim (Unix)
Src 'fzf.vim'
Src 'fzf-grep.vim'
Src 'coc.vim'
Src 'fugitive.vim'
...

call src#end()

```


## Commands
| Command                  | Description                                    |
| ------------------------ | ---------------------------------------------- |
| `Src [script path ...]`  | Load scripts                                   |
| `Src! [script path ...]` | Load scripts, ensuring their existence first.  |

**NOTE:** The `Src` command will load the current buffer if `script path` is left empty.


## License
MIT
