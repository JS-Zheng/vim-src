""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Definitions {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let g:src#version = '0.1.0'
let g:src#lib_name = 'vim-src'


" }}}
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Feature Test {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let s:is_win = has('win32')
let s:is_nvim = has('nvim')
let s:has_opt_shellslash = exists('+shellslash')

if has('patch-8.2.0868')
  let s:has_patch_8_2_0868 = 1
  " Add an argument to only trim the beginning or end.
  " https://github.com/vim/vim/commit/2245ae18e3480057f98fc0e5d9f18091f32a5de0
  let s:has_fn_dir_trim = 1
  let s:has_fn_trim = 1
elseif has('patch-8.0.1630')
  let s:has_patch_8_0_1630 = 1
  " Add the trim() function.
  " https://github.com/vim/vim/commit/295ac5ab5e840af6051bed5ec9d9acc3c73445de
  let s:has_fn_dir_trim = 0
  let s:has_fn_trim = 1
else
  let s:has_fn_dir_trim = 0
  let s:has_fn_trim = 0
endif


" }}}
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Public APIs {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Start a new script loading section
function! src#begin(...) abort
  " Determine the base directory for script loading
  if a:0 > 0
    let base_dir = s:abs_dir_path(a:1)
  elseif exists('g:src_base_dir')
    let base_dir = s:abs_dir_path(g:src_base_dir)
  else
    let base_dir = s:find_dflt_base_dir()
  endif

  " Resolve symbolic links if enabled
  if get(g:, 'src_resolve_links', 0)
    let base_dir = resolve(base_dir)
  endif

  " Debug message to display the base directory
  if get(g:, 'src_dbg', 0)
    echom '[vim-src] base dir: ' . base_dir
  endif

  " Push the determined base directory onto the stack
  call s:pushd(base_dir)
endfunction


" Source scripts specified by path or current buffer
" - (string | list) path: script filepath(s) to source
" - (int) validate: whether to check if the filepath is readable
function! src#(...) abort
  " Source the current buffer if no arguments are provided
  if a:0 == 0 || empty(a:1)
    source %
    return
  endif

  " Handle both single path and list of paths
  let paths = (type(a:1) == v:t_list) ? a:1 : [a:1]
  let validate = (a:0 > 1) ? a:2 : 0
  let base = s:get_base_dir()

  " Iterate through paths and source each script
  for path in paths
    call s:source(base, path, validate)
  endfor
endfunction


" End the current script loading section
function! src#end() abort
  " Pop the current base directory off the stack
  call s:popd()
endfunction


" }}}
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Private Functions {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Source {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:source(base, path, validate) abort
  let expanded_path = s:path_expand(a:path)
  let full_path = s:path_to_abs(a:base, expanded_path)

  if (a:validate) && (!filereadable(full_path))
    return -1
  endif

  let escaped_path = fnameescape(full_path)
  if get(g:, 'src_dbg', 0)
    echom '[vim-src] source ' . escaped_path
  endif
  execute 'source' escaped_path

  return 0
endfunction


" Push a directory onto the stack
function! s:pushd(dir) abort
  " Initialize the base directory stack if it doesn't exist
  if !exists('s:base_dir_stack')
    let s:base_dir_stack = []
  endif

  " Add a directory to the base directory stack
  call add(s:base_dir_stack, a:dir)
endfunction


" Pop the top directory from the stack
function! s:popd() abort
  " Return early if the stack is not initialized or empty
  if (!exists('s:base_dir_stack')) || (empty(s:base_dir_stack))
    return
  endif

  " Remove the top directory from the base directory stack
  call remove(s:base_dir_stack, -1)
endfunction


" Retrieve the current base directory
function! s:get_base_dir() abort
  " Use the current working directory if the stack is not initialized or empty
  if (!exists('s:base_dir_stack')) || (empty(s:base_dir_stack))
    return getcwd()
  endif

  " Return the top directory from the base directory stack
  return s:base_dir_stack[-1]
endfunction


" Find the default base directory for sourcing scripts
function! s:find_dflt_base_dir() abort
  " Prepare a list of potential data directories
  let data_dirs = []

  " Add Neovim's data directory to the list
  if s:is_nvim
    call add(data_dirs, stdpath('data'))
  endif

  " Add directories from the runtime path
  let data_dirs += split(&rtp, ',')

  " Default name for the base directory
  let base_dir_name = get(g:, 'src_base_dir_name', 'vimrcs')

  " Search through potential directories for a valid base directory
  for dir in data_dirs
    let base_dir = s:path_join([dir, base_dir_name])
    if isdirectory(base_dir)
      return base_dir
    endif
  endfor

  " Warn and throw an error if no valid base directory is found
  call s:warn('Unable to determine src base directory.')
  call s:warn('Try calling src#begin() with a path argument.')
  throw "Illegal Argument"
endfunction


" }}}
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Path {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
if s:is_win

  function! s:path_join(components) abort
    if !len(a:components)
      return ''
    endif

    " Start with an empty string
    let result = ''
    let sep = s:path_get_sep()

    " Iterate through each component
    for comp in a:components
      " If the component is an absolute path, reset the result string
      if s:path_is_abs(comp) || comp =~# '\v^[\/]'
        let result = comp
      else
        " Add a separator if the result doesn't already end with one and isn't empty
        if (result != '') && (!s:path_is_end_w_sep(result))
          let result .= sep
        endif

        " Concatenate the current component to the result
        let result .= comp
      endif
    endfor

    " Ensure the resulting path adheres to the trailing separator rule
    let last_comp = a:components[-1]
    if (!s:path_is_end_w_sep(result)) && (last_comp == '')
      let result .= sep
    endif

    " Return the constructed path
    return result
  endfunction

  function! s:path_expand(path) abort
    let expanded_path = s:unix_expand(a:path)

    " Handle the %VAR_NAME% format
    let pct_env_var_pat = '\v\%(\w+)\%'
    let expanded_path = substitute(expanded_path, pct_env_var_pat,
      \ '\=s:env_expand("$" . submatch(1), "%" . submatch(1) . "%")', 'g')

    return expanded_path
  endfunction


  function! s:path_is_abs(path) abort
    return a:path =~# '\v^%(//|\\\\|\a:/|\a:\\)'
  endfunction


  function! s:path_get_sep() abort
    return (s:is_shellslash()) ? '/' : '\'
  endfunction


  function! s:path_is_end_w_sep(path) abort
    return a:path =~# '[\/]$'
  endfunction

else

  function! s:path_join(components) abort
    if !len(a:components)
      return ''
    endif

    " Start with an empty string
    let result = ''

    " Iterate through each component
    for comp in a:components
      " If the component is an absolute path, reset the result string
      if s:path_is_abs(comp)
        let result = comp
      else
        " Add a separator if the result doesn't already end with one and isn't empty
        if (result != '') && (!s:path_is_end_w_sep(result))
          let result .= '/'
        endif

        " Concatenate the current component to the result
        let result .= comp
      endif
    endfor

    " Ensure the resulting path adheres to the trailing separator rule
    let last_comp = a:components[-1]
    if (!s:path_is_end_w_sep(result)) && (last_comp == '')
      let result .= '/'
    endif

    " Return the constructed path
    return result
  endfunction


  function! s:path_expand(path) abort
    return s:unix_expand(a:path)
  endfunction


  function! s:path_is_abs(path) abort
    return a:path =~# '^/'
  endfunction


  function! s:path_get_sep() abort
    return '/'
  endfunction

  function! s:path_is_end_w_sep(path) abort
    return a:path =~# '/$'
  endfunction

endif


" Generate an absolute directory path
function! s:abs_dir_path(dir) abort
  return fnamemodify(s:path_expand(a:dir), ':p:h')
endfunction


function! s:unix_expand(path)
  " Expand ~ to the home directory
  let expanded_path = substitute(a:path, '\v^[~]',
    \ '\=s:env_expand("~", "~")', '')

  " Expand environment variables
  let env_var_pat = '\v\$\w+'
  let expanded_path = substitute(expanded_path, env_var_pat,
    \ '\=s:env_expand(submatch(0), submatch(0))', 'g')

  " Handle the ${VAR_NAME} format
  let braced_env_var_pat = '\v\$\{(\w+)\}'
  let expanded_path = substitute(expanded_path, braced_env_var_pat,
    \ '\=s:env_expand("$" . submatch(1), "${" . submatch(1) . "}")', 'g')

  return expanded_path
endfunction


function! s:env_expand(env_var, fallback)
  if a:env_var =~# '\v\$\w+$'
    let evaluated = eval(a:env_var)
    if !empty(evaluated)
      return evaluated
    endif
  endif

  let expanded = expand(a:env_var)
  if expanded == a:env_var
    return a:fallback
  else
    return expanded
  endif
endfunction


if s:has_fn_dir_trim

  function! s:strip_slash(str) abort
    return trim(a:str, '\/', 0)
  endfunction


  function! s:strip_leading_slash(str) abort
    return trim(a:str, '\/', 1)
  endfunction


  function! s:strip_trailing_slash(str) abort
    return trim(a:str, '\/', 2)
  endfunction

else

  if s:has_fn_trim

    function! s:strip_slash(str) abort
      return trim(a:str, '\/')
    endfunction

  else

    function! s:strip_slash(str) abort
      return substitute(a:str, '\v^[\/]+|[\/]+$', '','g')
    endfunction

  endif


  function! s:strip_leading_slash(str) abort
    return substitute(a:str, '\v^[\/]+', '', '')
  endfunction


  function! s:strip_trailing_slash(str) abort
    return substitute(a:str, '\v[\/]+$', '', '')
  endfunction

endif


function! s:is_shellslash() abort
  if s:has_opt_shellslash
    return &shellslash
  endif

  return 0
endfunction


function! s:path_to_abs(base, path) abort
  if a:base == '' || s:path_is_abs(a:path)
    return a:path
  endif

  return s:path_join([a:base, a:path])
endfunction


" }}}
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Misc {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Define the Src command for sourcing scripts
function! s:def_commands() abort
  " The command allows sourcing of scripts with or without validation
  " -bang: allows use of '!' to indicate script existence check
  " -nargs=*: accepts any number of arguments (file paths)
  command! -bang -nargs=* Src call src#([<args>], <bang>0)
endfunction


function! s:warn(msg) abort
  echohl WarningMsg | echom a:msg | echohl None
endfunction


" }}}
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""


" }}}
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Init {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Initialize the stack for managing base directories
let s:base_dir_stack = []

" Define commands if necessary
if get(g:, 'src_def_commands', 1)
  call s:def_commands()
endif


" }}}
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" vim: sw=2 ts=2 tw=90 et foldmethod=marker
