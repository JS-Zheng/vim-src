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

" supported command-layer option keys
let s:CMD_OPTION_KEYS = ['optional', 'if']

" option keys normalized as booleans in command-layer parsing
let s:CMD_BOOL_OPTION_KEYS = ['optional', 'if']

" numeric/Boolean types accepted by public boolean options
let s:BOOL_SCALAR_TYPES = [v:t_number, v:t_float, type(v:true)]

" cache platform check results
let s:IS_WINDOWS = has('win32') || has('win64')


" non-zero once :Src command has been defined
let s:commands_defined = 0

" non-zero once a foreign :Src collision has been reported
let s:command_collision_reported = 0

" stack of directory contexts for relative path resolution
let s:ctx_stack = []

" protected stack depths owned by active source operations
let s:ctx_floor_stack = []

" cache key for the last successful default base-directory resolution
let s:default_dir_cache_key = ''

" cached result for the last successful default base-directory resolution
let s:default_dir_cache_value = ''


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
        if s:commands_defined
            let s:commands_defined = 1
            return
        endif

        let s:commands_defined = 0
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
    command! -nargs=* -bang Src call src#cmd('<bang>' ==# '!', <args>)
    let s:commands_defined = 1
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
" - src: invalid argument: unexpected argument count
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
        " Normalize CLI string arguments into a typed Dictionary.
        let opts = s:normalize_cmd_opts(a:2)
        let optional = get(opts, 'optional', 0) || optional
    endif

    if !get(opts, 'if', 1)
        return
    endif

    if type(target) == v:t_list
        call s:source_list(target, optional)
    else
        call s:source(target, optional)
    endif
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
        return s:source_buffer()
    endif

    let target = a:1
    call s:validate_target(target)
    let optional = s:normalize_bool(get(a:, 2, 0), 'optional')

    " Branch based on target type for fixed-arity core calls.
    if type(target) == v:t_list
        return s:source_list(target, optional)
    endif

    return s:source(target, optional)
endfunction


" Push a base-directory scope onto the resolution stack.
"
" Args:
" - [base_dir] (str): Absolute path or relative path resolved against
"   the current active scope. Omit for default base directory.
"
" Throws:
" - src: invalid argument: unexpected argument count
" - src: resolution failure: <PATH> not found
"
" Examples:
"   call src#begin()
"   call src#begin('~/.vim/vimrcs')
"   call src#begin('configs')
"   call src#begin('~/cfg-link')
"
function! src#begin(...) abort
    call s:init_cfg()
    if s:get_def_commands_cfg()
        \ && (!s:commands_defined || exists(':Src') != 2)
        call src#init()
    endif

    if a:0 == 0
        return s:begin_default()
    endif

    if a:0 == 1
        call s:require_string(a:1, 'path')
        return s:begin_explicit(a:1)
    endif

    call s:throw(g:src#ERR_INVALID_ARG, 'unexpected argument count')
endfunction


" Pop one base-directory scope from the stack. No-op when already empty.
function! src#end() abort
    call s:init_cfg()
    call s:end()
endfunction


" }}}
" ==============================================================================
"  Sourcing & Scope {{{
" ==============================================================================

" Source the contents of the current buffer.
"
" Throws:
" - src: source failure: current buffer ...
"
function! s:source_buffer() abort
    let context = s:current_buffer_failure_context()
    try
        let path = expand('%:p')
        if &buftype ==# '' && bufname('%') !=# '' && filereadable(path) && !&modified
            " Source from disk if buffer is unchanged;
            call s:source_script(path, fnamemodify(path, ':p:h'), context)
        else
            " otherwise, source from memory via temp file.
            call s:source_buffer_contents(s:buffer_context_dir(), context)
        endif
    catch
        if v:exception =~# '^src:'
            throw v:exception
        endif
        call s:error(context, v:exception, v:throwpoint)
        call s:throw(g:src#ERR_SOURCE, context)
    endtry
endfunction


" Entry point for sourcing a list of logical targets.
"
" Args:
" - targets (str[]): List of targets to be sourced.
" - optional (int): Non-zero to skip if unreadable.
"
function! s:source_list(targets, optional) abort
    for target in a:targets
        call s:source(target, a:optional)
    endfor
endfunction


" Push default base directory scope.
function! s:begin_default() abort
    let base = s:resolve_default_dir()
    call s:begin_with_base(base)
endfunction


" Push explicit path scope.
"
" Args:
" - path (str): Base directory path.
"
function! s:begin_explicit(path) abort
    let base = s:resolve_explicit_base_dir(a:path)
    call s:begin_with_base(base)
endfunction


" Pop the top base directory from the stack.
function! s:end() abort
    if empty(s:ctx_stack)
        return
    endif

    if !empty(s:ctx_floor_stack) && len(s:ctx_stack) <= s:ctx_floor_stack[-1]
        return
    endif

    call s:debug('end: ' .. s:ctx_stack[-1])
    call remove(s:ctx_stack, -1)
endfunction


" Core logic for base directory scope activation.
function! s:begin_with_base(base) abort
    call s:debug('begin: ' .. a:base)
    call s:push_ctx(a:base)
endfunction


" Internal dispatcher for sourcing a file or directory.
"
" Args:
" - path (str): Target path.
" - optional (int): Non-zero to skip if invalid.
"
" Throws:
" - src: invalid target: source target <PATH> not found
" - src: invalid target: file <PATH> is unreadable
" - src: invalid target: directory <PATH> is unreadable
"
function! s:source(path, optional) abort
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
" - path (str): Directory path.
" - optional (int): Non-zero to skip unreadable child targets.
"
function! s:source_dir(path, optional) abort
    let stack_depth = len(s:ctx_stack)
    let children = s:dir_vim_children(a:path)
    call s:push_ctx(a:path)
    try
        for child in children
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
    finally
        call s:restore_stack_depth(stack_depth)
    endtry
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
    call add(s:ctx_floor_stack, len(s:ctx_stack))

    try
        execute 'source ' .. s:escape_source_path(a:path)
    catch
        call s:error(a:failure_context, v:exception, v:throwpoint)
        call s:throw(g:src#ERR_SOURCE, a:failure_context)
    finally
        call remove(s:ctx_floor_stack, -1)
        call s:restore_stack_depth(stack_depth)
    endtry
endfunction


" Write buffer contents to a temporary file and source it.
function! s:source_buffer_contents(context_dir, failure_context) abort
    let tmp = tempname() .. '.vim'
    call writefile(getline(1, '$'), tmp)
    try
        call s:source_script(tmp, a:context_dir, a:failure_context)
    finally
        call delete(tmp)
    endtry
endfunction


" Determine the directory context for the current buffer.
function! s:buffer_context_dir() abort
    let path = expand('%:p')
    if empty(path)
        return ''
    endif

    return fnamemodify(path, ':p:h')
endfunction


" Generate a diagnostic string for buffer source failures.
function! s:current_buffer_failure_context() abort
    let path = expand('%:p')
    if empty(path)
        return 'current buffer'
    endif

    return 'current buffer: ' .. path
endfunction


" Restore the context stack to a specific depth.
function! s:restore_stack_depth(depth) abort
    while len(s:ctx_stack) > a:depth
        call remove(s:ctx_stack, -1)
    endwhile
endfunction


" Escape a file path for use with the :source command.
"
" Args:
" - path (str): Raw file path.
"
" Returns:
"   str: Escaped path.
"
function! s:escape_source_path(path) abort
    return fnameescape(a:path)
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


" Resolve and validate an explicit base directory.
"
" Args:
" - path (str): Candidate path.
"
" Returns:
"   str: Validated absolute path.
"
function! s:resolve_explicit_base_dir(path) abort
    let expanded = s:expand_tilde(a:path)
    if s:is_abs_path(expanded)
        return s:require_resolution_base(expanded)
    endif

    return s:require_resolution_base(
        \ s:join_path(s:current_resolution_base(), expanded)
        \ )
endfunction


" Find all direct *.vim file targets in a directory.
"
" Args:
" - path (str): Directory path.
"
" Returns:
"   dict[]: Loadable child target info entries.
"
" Throws:
" - src: invalid target: directory <PATH> is unreadable
"
function! s:dir_vim_children(path) abort
    try
        let names = readdir(a:path)
    catch
        call s:throw(g:src#ERR_INVALID_TARGET, 'directory ' .. a:path .. ' is unreadable')
    endtry
    if s:looks_unreadable_dir(a:path, names)
        call s:throw(g:src#ERR_INVALID_TARGET, 'directory ' .. a:path .. ' is unreadable')
    endif

    let children = []
    for name in names
        if name =~# '^\.'
            continue
        endif
        let full = s:join_path(a:path, name)
        let target = s:resolve_target_info(full)
        if target.kind ==# 'file' && name =~# '\.vim$'
            call add(children, target)
        endif
    endfor

    return sort(children, function('s:compare_target_basenames'))
endfunction


" Compare two classified targets by their directory-entry basenames.
function! s:compare_target_basenames(a, b) abort
    let ba = fnamemodify(a:a.entry_path, ':t')
    let bb = fnamemodify(a:b.entry_path, ':t')
    return ba <# bb ? -1 : ba ># bb ? 1 : 0
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
"   dict: Classified target info with resolved path and final filetype.
"
function! s:resolve_target_info(path) abort
    let info = {
          \ 'kind': 'missing',
          \ 'entry_path': a:path,
          \ 'path': a:path,
          \ 'ftype': '',
          \ }
    let ftype = getftype(a:path)

    if ftype ==# 'link'
        let info.path = s:normalize_path(resolve(a:path))
        let ftype = getftype(info.path)
    elseif ftype ==# 'file' || ftype ==# 'dir'
        let info.path = s:normalize_path(a:path)
    endif

    let info.ftype = ftype
    if ftype ==# 'file' || ftype ==# 'dir'
        let info.kind = ftype
    endif

    return info
endfunction


" Check if a directory matches the current context.
function! s:ctx_matches(dir) abort
    if empty(s:ctx_stack)
        return 0
    endif

    return s:ctx_stack[-1] ==# a:dir
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
" Throws:
" - src: resolution failure: path must be absolute: <PATH>
" - src: resolution failure: base directory not found for canonical config root
" - src: resolution failure: base directory not found for base_name: <NAME>
" - src: resolution failure: base directory not found: <PATH>
"
function! s:resolve_default_dir() abort
    let cache_key = s:default_dir_cache_key()
    if s:default_dir_cache_key ==# cache_key && !empty(s:default_dir_cache_value)
        return s:default_dir_cache_value
    endif

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
        if empty(base_name)
            let base_dir = s:resolve_base_dir_without_name()
            if empty(base_dir)
                call s:throw(
                    \ g:src#ERR_RESOLUTION,
                    \ 'base directory not found for canonical config root'
                    \ )
            endif
        else
            let base_dir = s:resolve_base_dir_with_name(base_name)
            if empty(base_dir)
                call s:throw(
                    \ g:src#ERR_RESOLUTION,
                    \ 'base directory not found for base_name: ' .. base_name
                    \ )
            endif
        endif
    endif

    let base_dir = s:require_resolution_base(base_dir)

    call s:debug('default_base_dir: ' .. base_dir)
    let s:default_dir_cache_key = cache_key
    let s:default_dir_cache_value = base_dir
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


" Return the path when it exists as a directory; otherwise return an empty
" string.
function! s:dir_if_exists(path) abort
    if isdirectory(a:path)
        return a:path
    endif

    return ''
endfunction


" Resolve a named base directory under common config roots.
"
" Notes:
"   This search order intentionally differs from
"   s:resolve_base_dir_without_name().
"
"   When a base name is provided (default: 'vimrcs'), users commonly place
"   the main init file and the named config directory side-by-side.
"   Therefore dir($MYVIMRC) has the highest priority here.
"
" Args:
" - base_name (str): Directory name to search for under candidate roots.
"
" Returns:
"   str: Resolved directory path, or an empty string when not found.
"
function! s:resolve_base_dir_with_name(base_name) abort
    if !empty($MYVIMRC)
        let dir = s:dir_if_exists(
            \ fnamemodify($MYVIMRC, ':p:h') .. '/' .. a:base_name
            \ )
        if !empty(dir)
            return dir
        endif
    endif

    if has('nvim')
        let dir = s:dir_if_exists(stdpath('config') .. '/' .. a:base_name)
        if !empty(dir)
            return dir
        endif
    endif

    let home = s:home_dir()

    if s:IS_WINDOWS
        let dir = s:dir_if_exists(home .. '/vimfiles/' .. a:base_name)
        if !empty(dir)
            return dir
        endif
    endif

    let dir = s:dir_if_exists(home .. '/.vim/' .. a:base_name)
    if !empty(dir)
        return dir
    endif

    let dir = s:dir_if_exists(s:xdg_config_home() .. '/vim/' .. a:base_name)
    if !empty(dir)
        return dir
    endif

    if !empty($VIM)
        let dir = s:dir_if_exists($VIM .. '/vimfiles/' .. a:base_name)
        if !empty(dir)
            return dir
        endif
    endif

    if !empty($VIMRUNTIME)
        let dir = s:dir_if_exists($VIMRUNTIME .. '/' .. a:base_name)
        if !empty(dir)
            return dir
        endif
    endif

    return ''
endfunction


" Resolve the default base directory without a named subdirectory.
"
" Notes:
"   This search order intentionally differs from
"   s:resolve_base_dir_with_name().
"
"   When no base name is configured, vim-src should prefer canonical
"   personal config roots such as stdpath('config'), ~/.vim, or ~/vimfiles.
"   It should not prioritize dir($MYVIMRC), because a common setup is:
"
"   $MYVIMRC = ~/.vimrc
"
"   In that case, dir($MYVIMRC) would resolve to $HOME, which is usually not
"   the intended base directory for modular Vim config files.
"
" Returns:
"   str: Resolved directory path, or an empty string when not found.
"
function! s:resolve_base_dir_without_name() abort
    if has('nvim')
        let dir = s:dir_if_exists(stdpath('config'))
        if !empty(dir)
            return dir
        endif
    endif

    let home = s:home_dir()

    if s:IS_WINDOWS
        let dir = s:dir_if_exists(home .. '/vimfiles')
        if !empty(dir)
            return dir
        endif
    endif

    let dir = s:dir_if_exists(home .. '/.vim')
    if !empty(dir)
        return dir
    endif

    let dir = s:dir_if_exists(s:xdg_config_home() .. '/vim')
    if !empty(dir)
        return dir
    endif

    if !empty($MYVIMRC)
        let dir = s:dir_if_exists(fnamemodify($MYVIMRC, ':p:h'))
        if !empty(dir)
            return dir
        endif
    endif

    if !empty($VIM)
        let dir = s:dir_if_exists($VIM .. '/vimfiles')
        if !empty(dir)
            return dir
        endif
    endif

    if !empty($VIMRUNTIME)
        let dir = s:dir_if_exists($VIMRUNTIME)
        if !empty(dir)
            return dir
        endif
    endif

    return ''
endfunction


" Build the cache key for default base-directory resolution.
function! s:default_dir_cache_key() abort
    return string([s:get_base_dir_cfg(), s:get_base_name_cfg()])
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
    " Check if a path is absolute on Windows.
    function! s:is_abs_path(path) abort
        return a:path =~# '^[A-Za-z]:[/\\]'
            \ || a:path =~# '^[/\\][/\\]'
            \ || a:path =~# '^[\/\\]'
    endfunction
else
    " Check if a path is absolute on Unix-like systems.
    function! s:is_abs_path(path) abort
        return a:path[0:0] ==# '/'
    endfunction
endif


" Concatenate a base directory and child entry safely.
"
" Args:
" - base (str): Base directory path.
" - child (str): Child entry path string.
"
" Returns:
"   str: Joined path string.
"
" Standardize slashes to avoid double-slash or missing-slash issues.
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
    if a:path ==# '~'
        return s:home_dir()
    endif

    " Manual ~ expansion to avoid unwanted environment variable interpolation
    " that standard expand() might trigger.
    if strlen(a:path) > 1
        let first = strpart(a:path, 0, 1)
        let second = strpart(a:path, 1, 1)
        if first ==# '~' && (second ==# '/' || second ==# '\')
            return s:home_dir() .. strpart(a:path, 1)
        endif
    endif

    return a:path
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

" Ensure command options are valid and typed correctly.
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

    return s:normalize_opts(a:opts, s:CMD_OPTION_KEYS, s:CMD_BOOL_OPTION_KEYS)
endfunction


" Normalize a typed options dictionary against an explicit schema.
"
" Args:
" - opts (dict): Raw option dictionary.
" - allowed_keys (str[]): Supported option keys.
" - bool_keys (str[]): Keys coerced to 0/1 boolean values.
"
" Returns:
"   dict: Normalized option dictionary.
"
" Throws:
" - src: invalid argument: unsupported option: ...
"
function! s:normalize_opts(opts, allowed_keys, bool_keys) abort
    let opts = {}
    for key in keys(a:opts)
        if index(a:allowed_keys, key) < 0
            call s:throw(g:src#ERR_INVALID_ARG, 'unsupported option: ' .. key)
        endif
        let opts[key] = a:opts[key]
    endfor

    for key in a:bool_keys
        if has_key(opts, key)
            let opts[key] = s:normalize_bool(opts[key], key)
        endif
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
"  Misc Helpers {{{
" ==============================================================================

" Return the home directory as a literal path, preferring $HOME.
function! s:home_dir() abort
    if exists('$HOME') && !empty($HOME)
        return $HOME
    endif
    return expand('~')
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
