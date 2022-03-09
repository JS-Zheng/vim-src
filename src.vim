""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Execution Guard {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
if exists('g:loaded_src')
  finish
endif

let g:loaded_src = 1


" }}}
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Feature Test {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let s:is_win = has('win32')
let s:is_nvim = has('nvim')

if (has('patch-8.2.0868'))
  let s:has_patch_8_2_0868 = 1

  " Add an argument to only trim the beginning or end.
  " https://github.com/vim/vim/commit/2245ae18e3480057f98fc0e5d9f18091f32a5de0
  let s:has_fn_dir_trim = 1
  let s:has_fn_trim = 1
elseif (has('patch-8.0.1630'))
  let s:has_patch_8_0_1630 = 1


  " Add the trim() function
  " https://github.com/vim/vim/commit/295ac5ab5e840af6051bed5ec9d9acc3c73445de
  let s:has_fn_dir_trim = 0
  let s:has_fn_trim = 1
else
  let s:has_fn_dir_trim = 0
  let s:has_fn_trim = 0
endif


" }}}
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Public APIs {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! src#begin(...) abort
  if (a:0 > 0)
    let base_dir = s:full_dir_path(a:1)
  elseif (exists('g:src_base_dir'))
    let base_dir = s:full_dir_path(g:src_base_dir)
  else
    let base_dir = s:get_dflt_base_dir()
  endif

  if (get(g:, 'src_resolve_links', 0))
    let base_dir = resolve(base_dir)
  endif

  call s:pushd(base_dir)
endfunction


" - (string | list) path: script filepath(s) to source
" - (int) validate: whether to check if the filepath is readable
function! src#(...) abort
  if a:0 == 0 || empty(a:1)
    source %
    return
  endif

  let l:paths = (type(a:1) == v:t_list) ? a:1 : [a:1]
  let l:validate = (a:0 > 1) ? a:2 : 0
  let l:base = s:get_base_dir()
  for l:path in l:paths
    call s:source(l:base, l:path, l:validate)
  endfor
endfunction


function! src#end() abort
  call s:popd()
endfunction


" }}}
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Private Functions {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:source(base, path, validate) abort
  let l:expanded_path = expand(a:path)
  let l:full_path = s:get_full_path(a:base, l:expanded_path)

  if (a:validate && !filereadable(l:full_path))
    return -1
  endif

  let l:escaped_path = fnameescape(l:full_path)
  if (get(g:, 'src_log', 0))
    echom '[vim-src] source ' . l:escaped_path
  endif
  execute 'source' l:escaped_path

  return 0
endfunction


function! s:nvim_dflt_base() abort
  return s:join_path(stdpath('data'), 'vimrcs')
endfunction


function! s:vim_dflt_base() abort
  return s:join_path(split(&rtp, ',')[0], 'vimrcs')
endfunction


function! s:def_commands() abort
  command! -bang -nargs=* Src call src#([<args>], <bang>0)
endfunction


function! s:get_dflt_base_dir() abort
  for Hdlr in s:dflt_base_handlers
    let base_dir = Hdlr()
    if (isdirectory(base_dir))
      return base_dir
    endif
  endfor

  call s:warn('Unable to determine src base directory.')
  call s:warn('Try calling src#begin() with a path argument.')
  throw "Illegale Argument"
endfunction


function! s:pushd(dir) abort
  if (!exists('s:base_dir_stack'))
    let s:base_dir_stack = []
  endif
  call add(s:base_dir_stack, a:dir)
endfunction


function! s:popd() abort
  if (!exists('s:base_dir_stack') || empty(s:base_dir_stack))
    return
  endif

  call remove(s:base_dir_stack, -1)
endfunction


function! s:get_base_dir() abort
  if (!exists('s:base_dir_stack') || empty(s:base_dir_stack))
    return getcwd()
  endif

  return s:base_dir_stack[-1]
endfunction


function! s:full_dir_path(dir) abort
  " Use `expand()` to expand environment variables
  return fnamemodify(expand(a:dir), ':p:h')
endfunction


function! s:warn(msg) abort
  echohl WarningMsg | echom a:msg | echohl None
endfunction


function! s:join_path(...) abort
  if (a:0 == 0)
    return ''
  end

  let i = 0
  let ret = ''
  let sep = s:get_sep()
  for path in a:000
    if (i == 0)
      let ret = s:strip_trailing_slash(path)
    else
      let ret .= (sep . s:strip_slash(path))
    endif
    let i += 1
  endfor

  return ret
endfunction


function! s:is_shellslash() abort
  if (exists('+shellslash'))
    return &shellslash
  endif

  return 0
endfunction


function! s:get_full_path(base, path) abort
  if a:base == '' || s:is_abs_path(a:path)
    return a:path
  endif

  return s:join_path(a:base, a:path)
endfunction


if (s:has_fn_dir_trim)

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

  if (s:has_fn_trim)

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


if (s:is_win)

  function! s:is_abs_path(path) abort
    if (s:is_shellslash())
      " \\\\ for UNC path
      return a:path =~# '\v^%(/|\\\\|\a:/)'
    else
      return a:path =~# '\v^%(\\|\a:\\)'
    endif
  endfunction


  function! s:get_sep() abort
    return (s:is_shellslash()) ? '/' : '\'
  endfunction

else

  function! s:is_abs_path(path) abort
    return a:path =~# '^/'
  endfunction


  function! s:get_sep() abort
    return '/'
  endfunction

endif


" }}}
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Init {{{
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let s:dflt_base_handlers = [function('s:vim_dflt_base')]
if (s:is_nvim)
  call insert(s:dflt_base_handlers, function('s:nvim_dflt_base'))
endif

let s:base_dir_stack = []

" Define commands if necessary
if (get(g:, 'src_def_commands', 1))
  call s:def_commands()
endif


" }}}
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

