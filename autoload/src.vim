" ==============================================================================
"  Compatibility {{{
" ==============================================================================

" Save the user's 'cpoptions' snapshot; temporarily set 'cpo' to Vim defaults,
" so Vi-compatible settings cannot misparse line continuations.
let s:SAVE_CPO = &cpo
set cpo&vim


" }}}
" ==============================================================================
"  Global/Script Vars {{{
" ==============================================================================

" Category for parameter errors, unsupported options, or type mismatches.
let g:src#ERR_INVALID_ARG = 'invalid argument'

" Category for failures in finding config homes or resolving scope roots.
let g:src#ERR_RESOLUTION = 'resolution failure'

" Category for missing, unreadable, or invalid files/directories targets.
let g:src#ERR_INVALID_TARGET = 'invalid target'

" Category for runtime failures during the :source command execution.
let g:src#ERR_SOURCE = 'source failure'


" default explicit base directory override
let s:DEFAULT_BASE_DIR = ''

" default named subdirectory under the resolved config root
let s:DEFAULT_BASE_NAME = 'vimrcs'

" whether to define the :Src command during bootstrap
let s:DEFAULT_DEF_COMMANDS = 1

" whether debug logging is enabled
let s:DEFAULT_DEBUG = 0

" supported command-layer option keys; all of them are booleans
let s:CMD_OPTION_KEYS = ['optional', 'if']

" numeric/Boolean types accepted by public boolean options
let s:BOOL_SCALAR_TYPES = [v:t_number, v:t_float, type(v:true)]

" cache platform check results
let s:IS_WINDOWS = has('win32') || has('win64')

" replacement text of the :Src command defined by src#def_cmds()
let s:SRC_CMD_DEFINITION = "call src#cmd('<bang>' ==# '!', <args>)"


" non-zero once a foreign :Src collision has been reported
let s:command_collision_reported = 0

" non-zero once the VimEnter cleanup of startup scopes has been registered
let s:startup_cleanup_registered = 0

" stack of directory contexts for relative path resolution
let s:ctx_stack = []

" protected stack depths owned by active source operations
let s:ctx_floor_stack = []



" }}}
" ==============================================================================
"  Public Functions {{{
" ==============================================================================

" Bootstrap vim-src for normal usage.
"
" Responsibilities:
" - ensure the g:src namespace exists
" - define commands when automatic command definition is enabled
" - preserve foreign commands and report namespace collisions
" - remain safe to call repeatedly
"
function! src#init() abort
    call s:init_cfg()
    if !s:get_def_commands_cfg()
        return
    endif

    if exists(':Src') == 2
        if s:owns_src_command()
            return
        endif

        if !s:command_collision_reported
            echohl WarningMsg
            echomsg '[vim-src] command collision: :Src already exists; '
                \ .. 'call src#def_cmds() to replace it'
            echohl None
            let s:command_collision_reported = 1
        endif
        return
    endif

    call src#def_cmds()
endfunction


" Define :Src command(s) explicitly.
"
" This lower-level API defines commands even when g:src.def_commands
" disables automatic bootstrap command definition.
"
function! src#def_cmds() abort
    execute 'command! -nargs=* -bang Src ' .. s:SRC_CMD_DEFINITION
    let s:command_collision_reported = 0
endfunction


" Command adapter used by :Src and :Src!.
"
" Args:
" - optional (int): 1 when invoked as :Src!, 0 when invoked as :Src
" - [target] (str|str[]): Logical target(s) to resolve and source.
" - [opts] (dict): Optional evaluated Vim Dict for command-layer options.
"
" Throws:
" - src: invalid argument: ... (argument count, types, or options)
" - errors from src#() for the target itself
"
function! src#cmd(optional, ...) abort
    call s:init_cfg()

    if a:0 > 2
        call s:throw(g:src#ERR_INVALID_ARG, 'unexpected argument count')
    endif

    let optional = s:normalize_bool(a:optional, 'optional')

    if a:0 == 0
        " No arguments: source the current buffer content.
        call s:source_buffer()
        return
    endif

    let target = a:1
    call s:validate_target(target)
    let opts = {}
    if a:0 == 2
        " Validate options and normalize their values to 0/1.
        let opts = s:normalize_cmd_opts(a:2)
        let optional = get(opts, 'optional', 0) || optional
    endif

    if !get(opts, 'if', 1)
        return
    endif

    call s:source_targets(target, optional)
endfunction


" Source paths, or the current buffer when called with no arguments.
"
" Args:
" - [target] (str|str[]): Logical target(s) to resolve and source,
"   or omitted for current buffer.
" - [optional] (int): Non-zero to silently skip missing/unreadable targets.
"
" Examples:
"   call src#()                  → source current buffer
"   call src#('file.vim')        → source a file or expand a directory
"   call src#(['a.vim', 'dir'])  → source each entry in order
"   call src#('local', 1)        → skip if missing
"
" Throws:
" - src: invalid argument: ... (argument count, target, or optional)
" - src: invalid target: ... (missing or unreadable target, unless optional)
" - src: resolution failure: ... (no base directory for a relative target)
" - src: source failure: ... (an error inside a sourced file)
"
" Notes:
" - Real filenames containing $ are not supported by :source.
"
function! src#(...) abort
    call s:init_cfg()

    if a:0 > 2
        call s:throw(g:src#ERR_INVALID_ARG, 'unexpected argument count')
    endif

    if a:0 == 0
        " Default to current buffer if no target is provided.
        call s:source_buffer()
        return
    endif

    call s:validate_target(a:1)
    call s:source_targets(a:1, s:normalize_bool(get(a:, 2, 0), 'optional'))
endfunction


" Push a base-directory scope onto the resolution stack.
"
" Args:
" - [base_dir] (str): Absolute path or relative path resolved against
"   the current active scope. Omit for default base directory.
"
" Throws:
" - src: invalid argument: unexpected argument count
" - src: invalid argument: path must be a String
" - src: invalid argument: path must not be empty
" - src: resolution failure: ... (see s:resolve_default_dir())
"
" Examples:
"   call src#begin()
"   call src#begin('~/.vim/vimrcs')
"   call src#begin('configs')
"   call src#begin('~/cfg-link')
"
function! src#begin(...) abort
    call src#init()

    if a:0 > 1
        call s:throw(g:src#ERR_INVALID_ARG, 'unexpected argument count')
    endif

    if a:0 == 0
        let base = s:resolve_default_dir()
    else
        " Like an empty target, an empty path usually comes from an unset
        " variable and would otherwise reopen the current scope silently.
        if empty(s:require_string(a:1, 'path'))
            call s:throw(g:src#ERR_INVALID_ARG, 'path must not be empty')
        endif
        let base = s:require_resolution_base(s:target_entry_path(a:1))
    endif
    call s:debug('begin: ' .. base)
    call s:register_startup_cleanup()
    call s:push_ctx(base)
endfunction


" Pop one base-directory scope from the stack.
"
" Notes:
" - No-op when no scope is open, or when the innermost scope belongs to a
"   caller of the file being sourced.
"
function! src#end() abort
    call s:init_cfg()
    if empty(s:ctx_stack)
        \ || !empty(s:ctx_floor_stack) && len(s:ctx_stack) <= s:ctx_floor_stack[-1]
        return
    endif

    call s:debug('end: ' .. s:ctx_stack[-1])
    call remove(s:ctx_stack, -1)
endfunction


" }}}
" ==============================================================================
"  Sourcing & Scope {{{
" ==============================================================================

" Source the current buffer: from disk when it is a clean file buffer,
" otherwise from its current contents through a temporary file.
"
" Notes:
" - Relative targets resolve against the buffer's directory, except in
"   $MYVIMRC: the editor rather than vim-src loads it, so a reload keeps the
"   startup resolution context.
" - Neovim picks the :source interpreter by extension, so Lua buffers keep a
"   .lua temp file.
"
" Throws:
" - src: source failure: current buffer[: <PATH>]
"
function! s:source_buffer() abort
    let path = expand('%:p')
    let context = empty(path) ? 'current buffer' : 'current buffer: ' .. path
    let context_dir = (empty(path) || s:is_myvimrc(path))
        \ ? '' : fnamemodify(path, ':p:h')
    try
        if &buftype ==# '' && !&modified && filereadable(path)
            call s:source_script(path, context_dir, context)
            return
        endif

        let is_lua = expand('%:e') ==? 'lua' || &filetype ==# 'lua'
        let tmp = tempname() .. (is_lua ? '.lua' : '.vim')
        call writefile(getline(1, '$'), tmp)
        try
            call s:source_script(tmp, context_dir, context)
        finally
            call delete(tmp)
        endtry
    catch /^src:/
        throw v:exception
    catch
        " Failures outside the sourced script, e.g. writing the temp file.
        call s:error(context, v:exception, v:throwpoint)
        call s:throw(g:src#ERR_SOURCE, context)
    endtry
endfunction


" Source a validated target: one logical path or a List of them, in order.
"
" Args:
" - target (str|str[]): Logical target(s) to resolve and source.
" - optional (int): Non-zero to skip missing or unreadable targets.
"
function! s:source_targets(target, optional) abort
    for path in type(a:target) == v:t_list ? a:target : [a:target]
        call s:source(path, a:optional)
    endfor
endfunction


" Close scopes still open when startup ends.
"
" Notes:
" - A failure rethrown from a vimrc aborts it before its src#end() calls,
"   which would otherwise leave every later :Src resolving inside a stale
"   scope for the whole session.
"
function! s:register_startup_cleanup() abort
    if v:vim_did_enter || s:startup_cleanup_registered
        return
    endif

    augroup src_startup_cleanup
        autocmd!
        autocmd VimEnter * call s:close_startup_scopes()
    augroup END
    let s:startup_cleanup_registered = 1
endfunction


" Drop scopes left open by startup and report how many were closed.
function! s:close_startup_scopes() abort
    autocmd! src_startup_cleanup
    if empty(s:ctx_stack)
        return
    endif

    let closed = len(s:ctx_stack)
    let s:ctx_stack = []
    let s:ctx_floor_stack = []
    echohl WarningMsg
    echomsg '[vim-src] closed ' .. closed .. ' src#begin() scope(s) left open by startup'
    echohl None
endfunction


" Internal dispatcher for sourcing a file or directory.
"
" Args:
" - path (str): Target path.
" - optional (int): Non-zero to skip if invalid.
"
" Throws:
" - src: invalid argument: target must not be empty
" - src: invalid target: source target <PATH> not found
" - src: invalid target: file <PATH> is unreadable
" - src: invalid target: directory <PATH> is unreadable
"
function! s:source(path, optional) abort
    " An empty target would otherwise resolve to the base directory itself
    " and load all of it, e.g. from an unset variable in `Src! $LOCAL`.
    if empty(a:path)
        if a:optional
            return
        endif
        call s:throw(g:src#ERR_INVALID_ARG, 'target must not be empty')
    endif

    let target = s:resolve_target_info(s:target_entry_path(a:path))

    call s:debug('source: ' .. target.path)

    if target.kind ==# 'file'
        if !filereadable(target.path)
            if a:optional
                return
            endif
            call s:throw(g:src#ERR_INVALID_TARGET, 'file ' .. a:path .. ' is unreadable')
        endif
        call s:source_file(target.path)

    elseif target.kind ==# 'dir'
        try
            call s:source_dir(target.path, a:optional)
        catch /^src: invalid target:/
            if !a:optional
                throw v:exception
            endif
        endtry

    else
        if a:optional
            return
        endif
        call s:throw(g:src#ERR_INVALID_TARGET, 'source target ' .. a:path .. ' not found')
    endif
endfunction


" Source a single Vimscript file.
function! s:source_file(path) abort
    call s:source_script(a:path, fnamemodify(a:path, ':p:h'), a:path)
endfunction


" Source all direct *.vim children of a directory.
"
" Args:
" - path (str): Resolved directory path.
" - optional (int): Non-zero to skip unreadable child targets.
"
" Notes:
" - Each child is sourced with its own directory as context, so the
"   directory itself needs no scope.
"
function! s:source_dir(path, optional) abort
    for child in s:dir_vim_children(a:path)
        if !filereadable(child.path)
            if a:optional
                continue
            endif
            call s:throw(
                \ g:src#ERR_INVALID_TARGET,
                \ 'file ' .. child.entry_path .. ' is unreadable'
                \ )
        endif
        call s:source_file(child.path)
    endfor
endfunction


" Low-level helper to source a path with a given context.
"
" Args:
" - path (str): Path to source.
" - context_dir (str): Directory for scope push.
" - failure_context (str): Diagnostic string.
"
" Throws:
" - src: source failure: <ERROR_MSG>
"
function! s:source_script(path, context_dir, failure_context) abort
    let stack_depth = len(s:ctx_stack)
    if !empty(a:context_dir) && !s:ctx_matches(a:context_dir)
        call s:push_ctx(a:context_dir)
    endif
    let floor_index = len(s:ctx_floor_stack)
    call add(s:ctx_floor_stack, len(s:ctx_stack))

    try
        execute 'source ' .. fnameescape(a:path)
    catch
        call s:error(a:failure_context, v:exception, v:throwpoint)
        call s:throw(g:src#ERR_SOURCE, a:failure_context)
    finally
        " Re-sourcing this script while it runs resets both stacks, so only
        " trim entries that still exist.
        if len(s:ctx_floor_stack) > floor_index
            call remove(s:ctx_floor_stack, floor_index, -1)
        endif
        if len(s:ctx_stack) > stack_depth
            call remove(s:ctx_stack, stack_depth, -1)
        endif
    endtry
endfunction


" Check whether a path refers to the startup vimrc ($MYVIMRC).
function! s:is_myvimrc(path) abort
    if empty($MYVIMRC)
        return 0
    endif

    let vimrc = resolve(fnamemodify($MYVIMRC, ':p'))
    let path = resolve(fnamemodify(a:path, ':p'))
    if !s:IS_WINDOWS
        return vimrc ==# path
    endif

    " Vim on MS-Windows keeps mixed separators, and file names ignore case.
    return tr(vimrc, '\', '/') ==? tr(path, '\', '/')
endfunction


" Resolve a target path relative to the current context.
"
" Args:
" - path (str): Relative or absolute target path.
"
" Returns:
"   str: Expanded absolute path.
"
function! s:target_entry_path(path) abort
    let expanded = s:expand_tilde(a:path)
    if s:is_abs_path(expanded)
        return expanded
    endif

    " Resolve relative to current stack top.
    return s:join_path(s:current_resolution_base(), expanded)
endfunction


" Identify the current base directory for path resolution.
"
" Returns:
"   str: Absolute base path.
"
function! s:current_resolution_base() abort
    if !empty(s:ctx_stack)
        return s:ctx_stack[-1]
    endif

    return s:resolve_default_dir()
endfunction


" Find all direct *.vim file targets in a directory.
"
" Args:
" - path (str): Resolved directory path.
"
" Returns:
"   dict[]: Loadable child target info entries.
"
" Throws:
" - src: invalid target: directory <PATH> is unreadable
"
" Notes:
" - Errors name the resolved path on purpose, which shows where a symlinked
"   target actually points.
"
function! s:dir_vim_children(path) abort
    let unreadable = 'directory ' .. a:path .. ' is unreadable'
    try
        let names = s:read_dir_names(a:path)
    catch
        call s:throw(g:src#ERR_INVALID_TARGET, unreadable)
    endtry
    if s:looks_unreadable_dir(a:path, names)
        call s:throw(g:src#ERR_INVALID_TARGET, unreadable)
    endif

    " Visible *.vim names only; sorting the names gives the byte-wise lexical
    " load order.
    let children = []
    for name in sort(filter(copy(names), 'v:val =~# ''^[^.].*\.vim$'''))
        let target = s:resolve_target_info(s:join_path(a:path, name))
        if target.kind ==# 'file'
            call add(children, target)
        endif
    endfor
    return children
endfunction


" List the non-hidden entry names of a directory.
"
" Notes:
" - readdir() is unavailable before Neovim 0.5, so fall back to glob() with
"   the directory path escaped as a literal pattern. Hidden entries are
"   skipped by callers, so the '*' pattern not matching them is harmless.
"
function! s:read_dir_names(path) abort
    if exists('*readdir')
        return readdir(a:path)
    endif

    if s:IS_WINDOWS
        let pattern = substitute(a:path, '[[*?{}$`'']', '[&]', 'g')
    else
        let pattern = escape(a:path, '\[]*?{}$`''')
    endif
    let pattern = substitute(pattern, '[/\\]\+$', '', '') .. '/*'

    return map(glob(pattern, 1, 1, 1), 'fnamemodify(v:val, ":t")')
endfunction


" Best-effort probe for directories that some runtimes expose as empty
" instead of raising from readdir().
function! s:looks_unreadable_dir(path, names) abort
    if !isdirectory(a:path)
        return 0
    endif

    " Searching a directory is an effective-access operation and therefore
    " accounts for the process identity and platform access controls.
    if getftype(s:join_path(a:path, '.')) !=# 'dir'
        return 1
    endif

    " A non-empty result proves that the runtime could read directory entries.
    if !empty(a:names) || !exists('*getfperm')
        return 0
    endif

    let perms = getfperm(a:path)
    if empty(perms)
        return 0
    endif

    " When readdir() masks EACCES as an empty result, absence of every read bit
    " is the remaining portable Vimscript-level evidence. Search access was
    " verified above, so group/other-readable directories are retained.
    return perms !~# 'r'
endfunction


" Classify a concrete path as a file, directory, or missing target.
"
" Args:
" - path (str): Concrete absolute or relative path to inspect.
"
" Returns:
"   dict: {kind: 'file'|'dir'|'missing', entry_path: as given, path: the
"   normalized path with a symlink resolved to its target}
"
function! s:resolve_target_info(path) abort
    let path = getftype(a:path) ==# 'link' ? resolve(a:path) : a:path
    let ftype = getftype(path)
    if ftype !=# 'file' && ftype !=# 'dir'
        return {'kind': 'missing', 'entry_path': a:path, 'path': a:path}
    endif

    return {'kind': ftype, 'entry_path': a:path, 'path': s:normalize_path(path)}
endfunction


" Check if a directory matches the current context.
"
" Notes:
" - ':p' keeps a trailing separator on directories and ':p:h' drops it, so
"   compare without trailing separators.
"
function! s:ctx_matches(dir) abort
    if empty(s:ctx_stack)
        return 0
    endif

    let pattern = '[/\\]\+$'
    return substitute(s:ctx_stack[-1], pattern, '', '')
        \ ==# substitute(a:dir, pattern, '', '')
endfunction


" Push a new context onto the stack.
function! s:push_ctx(dir) abort
    call add(s:ctx_stack, a:dir)
endfunction


" }}}
" ==============================================================================
"  Base Directory Resolution {{{
" ==============================================================================

" Resolve the default base directory from user configuration and editor state.
"
" Resolution policy:
" - If g:src.base_dir is set, treat it as an explicit absolute-path
"   override.
" - Otherwise, if g:src.base_name is non-empty, resolve a named subdirectory
"   under the preferred config roots.
" - Otherwise, resolve a canonical base config directory directly.
"
" Returns:
"   str: Absolute path to the resolved base directory.
"
" Notes:
" - Not cached: the search is a few isdirectory() checks, and a cache would
"   go stale when directories or environment variables change.
"
" Throws:
" - src: invalid argument: g:src.base_dir/base_name must be a String
" - src: resolution failure: path must be absolute: <PATH>
" - src: resolution failure: base directory not found for canonical config root
" - src: resolution failure: base directory not found for base_name: <NAME>
" - src: resolution failure: <PATH> not found
"
function! s:resolve_default_dir() abort
    let configured_base_dir = s:get_base_dir_cfg()
    if !empty(configured_base_dir)
        let base_dir = s:expand_tilde(configured_base_dir)
        if !s:is_abs_path(base_dir)
            call s:throw(
                \ g:src#ERR_RESOLUTION,
                \ 'path must be absolute: ' .. base_dir
                \ )
        endif
    else
        let base_name = s:get_base_name_cfg()
        let base_dir = s:find_base_dir(base_name)
        if empty(base_dir)
            call s:throw(
                \ g:src#ERR_RESOLUTION,
                \ empty(base_name)
                \     ? 'base directory not found for canonical config root'
                \     : 'base directory not found for base_name: ' .. base_name
                \ )
        endif
    endif

    let base_dir = s:require_resolution_base(base_dir)
    call s:debug('default_base_dir: ' .. base_dir)
    return base_dir
endfunction


" Return the normalized XDG config home directory.
"
" Notes:
" - The XDG specification requires this value to be absolute. Ignoring a
"   relative value also prevents resolution from depending on getcwd().
"
function! s:xdg_config_home() abort
    if !empty($XDG_CONFIG_HOME) && s:is_abs_path($XDG_CONFIG_HOME)
        return s:normalize_path($XDG_CONFIG_HOME)
    endif

    return s:normalize_path(s:home_dir() .. '/.config')
endfunction


" Return the config roots searched for a base directory, in priority order.
"
" Notes:
"   The order depends on whether a base name is configured.
"
"   With a base name (default: 'vimrcs'), users commonly place the main init
"   file and the named config directory side by side, so dir($MYVIMRC) comes
"   first.
"
"   Without one, canonical personal config roots such as stdpath('config'),
"   ~/.vim, or ~/vimfiles come first. dir($MYVIMRC) is demoted because a
"   common setup is $MYVIMRC = ~/.vimrc, where it would resolve to $HOME,
"   which is usually not the intended base directory.
"
" Args:
" - named (int): Non-zero when a base name is configured.
"
" Returns:
"   str[]: Candidate roots; unavailable roots are empty strings.
"
function! s:config_roots(named) abort
    let home = s:home_dir()
    let vimrc_dir = empty($MYVIMRC) ? '' : fnamemodify($MYVIMRC, ':p:h')

    let roots = a:named ? [vimrc_dir] : []
    if has('nvim')
        call add(roots, stdpath('config'))
    endif
    if s:IS_WINDOWS
        call add(roots, home .. '/vimfiles')
    endif
    call extend(roots, [home .. '/.vim', s:xdg_config_home() .. '/vim'])
    if !a:named
        call add(roots, vimrc_dir)
    endif
    return roots + [empty($VIM) ? '' : $VIM .. '/vimfiles', $VIMRUNTIME]
endfunction


" Find the first existing base directory under the config roots.
"
" Args:
" - base_name (str): Named subdirectory to look for, or empty to use the
"   roots themselves.
"
" Returns:
"   str: Resolved directory path, or an empty string when not found.
"
function! s:find_base_dir(base_name) abort
    for root in s:config_roots(!empty(a:base_name))
        if empty(root)
            continue
        endif
        let dir = empty(a:base_name) ? root : root .. '/' .. a:base_name
        if isdirectory(dir)
            return dir
        endif
    endfor
    return ''
endfunction


" }}}
" ==============================================================================
"  Configuration {{{
" ==============================================================================

" Ensure the g:src namespace is correctly initialized as a Dictionary.
"
function! s:init_cfg() abort
    if !exists('g:src') || type(g:src) != v:t_dict
        let g:src = {}
    endif
endfunction


" Get a configuration value from the g:src namespace with a fallback.
"
" Args:
" - key (str): Configuration key string.
" - default (any): Fallback value if the key is missing.
"
" Returns:
"   any: The configured value or the provided default.
"
function! s:get_cfg(key, default) abort
    return get(get(g:, 'src', {}), a:key, a:default)
endfunction


" Get the configured explicit base directory override.
function! s:get_base_dir_cfg() abort
    return s:require_string(
        \ s:get_cfg('base_dir', s:DEFAULT_BASE_DIR),
        \ 'g:src.base_dir'
        \ )
endfunction


" Get the configured named base directory token.
function! s:get_base_name_cfg() abort
    return s:require_string(
        \ s:get_cfg('base_name', s:DEFAULT_BASE_NAME),
        \ 'g:src.base_name'
        \ )
endfunction


" Check if automatic command definition is enabled.
function! s:get_def_commands_cfg() abort
    return s:normalize_bool(
        \ s:get_cfg('def_commands', s:DEFAULT_DEF_COMMANDS),
        \ 'g:src.def_commands'
        \ )
endfunction


" Check if debug logging is enabled.
function! s:get_debug_cfg() abort
    return s:normalize_bool(
        \ s:get_cfg('debug', s:DEFAULT_DEBUG),
        \ 'g:src.debug'
        \ )
endfunction


" Check whether :Src is the command defined by src#def_cmds().
"
" Notes:
" - Ownership is decided by the exact definition rather than script state,
"   so re-sourcing this script does not mistake its own :Src for a foreign
"   command, while foreign commands that merely mention src#cmd stay foreign.
" - A buffer-local :Src may be listed alongside the global one, so any
"   matching definition counts.
"
function! s:owns_src_command() abort
    if exists(':Src') != 2
        return 0
    endif

    let definition = s:SRC_CMD_DEFINITION
    for line in split(execute('command Src'), "\n")
        if line =~# '^\S*\s\+Src\s'
            \ && strpart(line, len(line) - len(definition)) ==# definition
            return 1
        endif
    endfor
    return 0
endfunction


" }}}
" ==============================================================================
"  Diagnostic {{{
" ==============================================================================

" Throw a standardized library error following the project contract.
"
" Args:
" - kind (str): Error category (e.g., g:src#ERR_INVALID_ARG).
" - detail (str): Specific failure description.
"
function! s:throw(kind, detail) abort
    throw 'src: ' .. a:kind .. ': ' .. a:detail
endfunction


" Print a formatted failure report to the user messages.
"
" Args:
" - context (str): Diagnostic string describing where it failed.
" - exception (str): The original raw exception message.
" - throwpoint (str): Original Vim throw location.
"
function! s:error(context, exception, throwpoint) abort
    echohl ErrorMsg
    echomsg '[vim-src] source failed: ' .. a:context
    echomsg '[vim-src] original error: ' .. a:exception
    echomsg '[vim-src] throwpoint: ' .. a:throwpoint
    echohl None
endfunction


" Print a debug message if logging is enabled in configuration.
"
" Args:
" - msg (str): Message text to log.
"
function! s:debug(msg) abort
    if s:get_debug_cfg()
        echomsg '[vim-src] ' .. a:msg
    endif
endfunction


" }}}
" ==============================================================================
"  Path {{{
" ==============================================================================

if s:IS_WINDOWS
    " Check if a path is absolute on Windows (drive, UNC, or rooted path).
    function! s:is_abs_path(path) abort
        return a:path =~# '^[A-Za-z]:[/\\]' || a:path =~# '^[/\\]'
    endfunction
else
    " Check if a path is absolute on Unix-like systems.
    function! s:is_abs_path(path) abort
        return a:path[0:0] ==# '/'
    endfunction
endif


" Join a base directory and a child entry with exactly one '/' between them.
"
" Args:
" - base (str): Base directory path.
" - child (str): Child entry path string.
"
" Returns:
"   str: Joined path string.
"
function! s:join_path(base, child) abort
    return substitute(a:base, '[/\\]\+$', '', '') .. '/' .. a:child
endfunction


" Robustly expand ~ prefix without triggering environment expansion.
"
" Args:
" - path (str): Path string potentially containing ~.
"
" Returns:
"   str: Path with ~ expanded to home directory.
"
function! s:expand_tilde(path) abort
    " Expand only '~' and '~/' or '~\' by hand: expand() would also
    " interpolate environment variables and wildcards in the rest of the path.
    if a:path =~# '^\~\%([/\\]\|$\)'
        return s:home_dir() .. strpart(a:path, 1)
    endif

    return a:path
endfunction


" Return the home directory as a literal path, preferring $HOME.
function! s:home_dir() abort
    if exists('$HOME') && !empty($HOME)
        return $HOME
    endif
    return expand('~')
endfunction


" Normalize a path to its absolute simplified form.
"
" Args:
" - path (str): Path string.
"
" Returns:
"   str: Normalized absolute path.
"
function! s:normalize_path(path) abort
    return fnamemodify(a:path, ':p')
endfunction


" Canonicalize and validate a directory used as a resolution base.
"
" Args:
" - path (str): Path to resolve.
"
" Returns:
"   str: Absolute path to the resolved target.
"
" Throws:
" - src: resolution failure: path must be absolute: <PATH>
" - src: resolution failure: <PATH> not found
"
function! s:require_resolution_base(path) abort
    let resolved = resolve(a:path)
    if !s:is_abs_path(resolved)
        call s:throw(g:src#ERR_RESOLUTION, 'path must be absolute: ' .. resolved)
    endif

    return s:require_dir(resolved)
endfunction


" Ensure a path exists and is a directory.
"
" Args:
" - path (str): Candidate path string.
"
" Returns:
"   str: Validated absolute path.
"
" Throws:
" - src: resolution failure: <PATH> not found
"
function! s:require_dir(path) abort
    let base = s:normalize_path(a:path)
    if !isdirectory(base)
        call s:throw(g:src#ERR_RESOLUTION, base .. ' not found')
    endif

    return base
endfunction


" }}}
" ==============================================================================
"  Option Normalization {{{
" ==============================================================================

" Validate command options and normalize their values to 0/1.
"
" Args:
" - opts (dict): Command options.
"
" Returns:
"   dict: Normalized options.
"
" Throws:
" - src: invalid argument: opts must be a Dictionary
" - src: invalid argument: unsupported option: ...
"
function! s:normalize_cmd_opts(opts) abort
    if type(a:opts) != v:t_dict
        call s:throw(g:src#ERR_INVALID_ARG, 'opts must be a Dictionary')
    endif

    " Report unsupported keys before value errors, independent of key order.
    for key in keys(a:opts)
        if index(s:CMD_OPTION_KEYS, key) < 0
            call s:throw(g:src#ERR_INVALID_ARG, 'unsupported option: ' .. key)
        endif
    endfor

    let opts = {}
    for [key, value] in items(a:opts)
        let opts[key] = s:normalize_bool(value, key)
    endfor
    return opts
endfunction


" Validate a public target as a String or a List containing only Strings.
function! s:validate_target(target) abort
    if type(a:target) == v:t_string
        return
    endif

    if type(a:target) != v:t_list
        call s:throw(
            \ g:src#ERR_INVALID_ARG,
            \ 'target must be a String or List of Strings'
            \ )
    endif

    let index = 0
    for target in a:target
        if type(target) != v:t_string
            call s:throw(
                \ g:src#ERR_INVALID_ARG,
                \ 'target[' .. index .. '] must be a String'
                \ )
        endif
        let index += 1
    endfor
endfunction


" Return a String value or throw a public argument error naming its field.
function! s:require_string(value, label) abort
    if type(a:value) != v:t_string
        call s:throw(g:src#ERR_INVALID_ARG, a:label .. ' must be a String')
    endif
    return a:value
endfunction


" Normalize numeric truthiness while rejecting Strings and containers.
function! s:normalize_bool(value, label) abort
    if index(s:BOOL_SCALAR_TYPES, type(a:value)) < 0
        call s:throw(
            \ g:src#ERR_INVALID_ARG,
            \ a:label .. ' must be a Number, Float, or Boolean'
            \ )
    endif
    if type(a:value) == v:t_float
        return a:value != 0.0
    endif
    return a:value != 0
endfunction


" }}}
" ==============================================================================
"  Compatibility Restore {{{
" ==============================================================================

let &cpo = s:SAVE_CPO
unlet s:SAVE_CPO


" }}}
" ==============================================================================
" vim: ft=vim sw=4 ts=4 et foldmethod=marker
