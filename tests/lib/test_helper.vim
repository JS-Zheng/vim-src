" Format assertion context into stable key=value diagnostics.
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


" Assert equality with formatted test context on failure.
function! SrcTestAssertEqual(expected, got, ctx) abort
    execute 'AssertEqual a:expected, a:got, SrcTestFormatCtx(a:ctx)'
endfunction


" Assert a pattern match with formatted test context on failure.
function! SrcTestAssertMatch(pattern, got, ctx) abort
    execute 'Assert a:got =~# a:pattern, SrcTestFormatCtx(a:ctx)'
endfunction


" Return a rooted path using native Windows separators when applicable.
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


" Return an absolute path using forward slashes on Windows.
function! SrcTestWindowsSlashPath(path) abort
    let l:path = fnamemodify(a:path, ':p')

    if has('win32') || has('win64')
        return substitute(l:path, '\', '/', 'g')
    endif

    return l:path
endfunction


" Return an absolute path using backslashes on Windows.
function! SrcTestWindowsBackslashPath(path) abort
    let l:path = fnamemodify(a:path, ':p')

    if has('win32') || has('win64')
        return substitute(l:path, '/', '\', 'g')
    endif

    return l:path
endfunction


" Remove read access from a test path.
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


" Set an exact Unix mode or fail when chmod is unavailable.
function! SrcTestSetUnixMode(path, mode) abort
    if executable('chmod')
        call system('chmod ' .. shellescape(a:mode) .. ' ' .. shellescape(a:path))
        return
    endif

    throw 'src-test: chmod is required for explicit Unix mode tests'
endfunction


" Restore owner access to a test path.
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
