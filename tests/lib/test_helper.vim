function! SrcTestInitCandidates(platform, ...) abort
  if a:platform ==# 'unix'
    return s:UnixInitCandidates(a:1, a:2)
  endif

  if a:platform ==# 'windows'
    return s:WindowsInitCandidates(a:1, a:2)
  endif

  if a:platform ==# 'nvim'
    return s:NvimInitCandidates(a:1)
  endif

  throw 'src-test: unknown platform'
endfunction


function! SrcTestConfigHomeFromVimrc(platform, vimrc, ...) abort
  for l:candidate in call('SrcTestInitCandidates', [a:platform] + a:000)
    if l:candidate.vimrc ==# a:vimrc
      return l:candidate.config_home
    endif
  endfor

  return ''
endfunction


function! s:UnixInitCandidates(home, xdg_home) abort
  let l:home = trim(a:home, '\/', 2)
  let l:xdg = trim(a:xdg_home, '\/', 2)
  let l:candidates = []

  if !empty(l:home)
    call add(l:candidates, {'vimrc': l:home . '/.vimrc', 'config_home': l:home . '/.vim'})
    call add(l:candidates, {'vimrc': l:home . '/.vim/vimrc', 'config_home': l:home . '/.vim'})
    call add(l:candidates, {'vimrc': l:home . '/_vimrc', 'config_home': l:home . '/.vim'})
  endif

  if !empty(l:xdg)
    call add(l:candidates, {'vimrc': l:xdg . '/vim/vimrc', 'config_home': l:xdg . '/vim'})
  endif

  return l:candidates
endfunction


function! s:WindowsInitCandidates(home, vim_dir) abort
  let l:home = s:WindowsJoin(trim(a:home, '\/', 2), '')
  let l:vim = s:WindowsJoin(trim(a:vim_dir, '\/', 2), '')
  let l:candidates = []

  if !empty(l:home)
    call add(l:candidates, {'vimrc': s:WindowsJoin(l:home, '_vimrc'), 'config_home': s:WindowsJoin(l:home, 'vimfiles')})
    call add(l:candidates, {'vimrc': s:WindowsJoin(l:home, 'vimfiles\vimrc'), 'config_home': s:WindowsJoin(l:home, 'vimfiles')})
    call add(l:candidates, {'vimrc': s:WindowsJoin(l:home, '.vimrc'), 'config_home': s:WindowsJoin(l:home, 'vimfiles')})
  endif

  if !empty(l:vim)
    call add(l:candidates, {'vimrc': s:WindowsJoin(l:vim, '_vimrc'), 'config_home': s:WindowsJoin(l:vim, 'vimfiles')})
    call add(l:candidates, {'vimrc': s:WindowsJoin(l:vim, '.vimrc'), 'config_home': s:WindowsJoin(l:vim, 'vimfiles')})
  endif

  return l:candidates
endfunction


function! s:NvimInitCandidates(config_home) abort
  let l:config_home = trim(a:config_home, '\/', 2)
  return [
    \ {'vimrc': l:config_home . '/init.lua', 'config_home': l:config_home},
    \ {'vimrc': l:config_home . '/init.vim', 'config_home': l:config_home},
    \ ]
endfunction


function! s:WindowsJoin(base, leaf) abort
  let l:base = substitute(a:base, '/', '\', 'g')
  let l:base = trim(l:base, '\', 2)
  let l:leaf = substitute(a:leaf, '/', '\', 'g')

  if empty(l:leaf)
    return l:base
  endif

  return empty(l:base) ? l:leaf : l:base . '\' . l:leaf
endfunction


function! SrcTestFormatCtx(ctx) abort
  let l:ordered_keys = [
        \ 'case',
        \ 'target',
        \ 'rooted',
        \ 'base_dir',
        \ 'cwd',
        \ 'exception',
        \ 'throwpoint',
        \ 'messages',
        \ 'notes',
        \ ]
  let l:parts = []

  for l:key in l:ordered_keys
    if has_key(a:ctx, l:key) && !empty(a:ctx[l:key])
      call add(l:parts, l:key .. '=' .. string(a:ctx[l:key]))
    endif
  endfor

  return join(l:parts, ' | ')
endfunction


function! SrcTestAssertEqual(expected, got, ctx) abort
  execute 'AssertEqual a:expected, a:got, SrcTestFormatCtx(a:ctx)'
endfunction


function! SrcTestAssertMatch(pattern, got, ctx) abort
  execute 'Assert a:got =~# a:pattern, SrcTestFormatCtx(a:ctx)'
endfunction


function! SrcTestWindowsRootedPath(path) abort
  let l:path = fnamemodify(a:path, ':p')

  if has('win32') || has('win64')
    let l:path = substitute(l:path, '/', '\', 'g')
    if l:path =~# '^\a:'
      return strpart(l:path, 2)
    endif
  endif

  return l:path
endfunction


function! SrcTestWindowsSlashPath(path) abort
  let l:path = fnamemodify(a:path, ':p')

  if has('win32') || has('win64')
    return substitute(l:path, '\', '/', 'g')
  endif

  return l:path
endfunction


function! SrcTestWindowsBackslashPath(path) abort
  let l:path = fnamemodify(a:path, ':p')

  if has('win32') || has('win64')
    return substitute(l:path, '/', '\', 'g')
  endif

  return l:path
endfunction


function! SrcTestMakeUnreadable(path, kind) abort
  if executable('chmod')
    if a:kind ==# 'dir'
      call system('chmod 000 ' .. shellescape(a:path))
    else
      call system('chmod 000 ' .. shellescape(a:path))
    endif
    return
  endif

  call setfperm(a:path, '---------')
endfunction


function! SrcTestRestoreReadable(path, kind) abort
  if executable('chmod')
    if a:kind ==# 'dir'
      call system('chmod 700 ' .. shellescape(a:path))
    else
      call system('chmod 600 ' .. shellescape(a:path))
    endif
    return
  endif

  if a:kind ==# 'dir'
    call setfperm(a:path, 'rwx------')
  else
    call setfperm(a:path, 'rw-------')
  endif
endfunction
