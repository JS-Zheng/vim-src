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

" Category for internal state corruption or namespace pollution (e.g., g:src).
let g:src#ERR_INVALID_STATE = 'invalid state'

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

" whether to follow symbolic links by default
let s:DEFAULT_FOLLOW_LINKS = 1

" whether to define the :Src command during bootstrap
let s:DEFAULT_DEF_COMMANDS = 1

" whether debug logging is enabled
let s:DEFAULT_DEBUG = 0

" supported command-layer option keys
let s:CMD_OPTION_KEYS = ['optional', 'follow_links', 'if']

" supported scope-layer option keys
let s:BEGIN_OPTION_KEYS = ['follow_links']

" option keys normalized as booleans in command-layer parsing
let s:CMD_BOOL_OPTION_KEYS = ['optional', 'follow_links', 'if']

" option keys normalized as booleans in scope-layer parsing
let s:BEGIN_BOOL_OPTION_KEYS = ['follow_links']

" option keys merged into effective execution options
let s:EFFECTIVE_OPTION_KEYS = ['follow_links']

" cache platform check results
let s:IS_WINDOWS = has('win32') || has('win64')


" non-zero once :Src command has been defined
let s:commands_defined = 0

" stack of directory contexts for relative path resolution
let s:ctx_stack = []

" cache key for the last successful default base-directory resolution
let s:default_dir_cache_key = ''

" cached result for the last successful default base-directory resolution
let s:default_dir_cache_value = ''


" }}}
" ==============================================================================
"  Public Functions {{{
" ==============================================================================

function! src#init() abort
    " Bootstrap vim-src for normal usage.
    "
    " Responsibilities:
    " - ensure the g:src namespace exists
    " - define commands when automatic command definition is enabled
    " - remain safe to call repeatedly
    "
    call s:init_cfg()
    if !s:commands_ready() && s:get_def_commands_cfg()
        call src#def_cmds()
    endif
endfunction


function! src#def_cmds() abort
    " Define :Src command(s) explicitly.
    "
    " This lower-level API defines commands even when g:src.def_commands
    " disables automatic bootstrap command definition.
    "
    command! -nargs=* -bang Src call src#cmd('<bang>' ==# '!', <args>)
    let s:commands_defined = 1
endfunction


function! src#cmd(optional, ...) abort
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
    call s:init_cfg()

    if a:0 > 2
        call s:throw(g:src#ERR_INVALID_ARG, 'unexpected argument count')
    endif

    if a:0 == 0
        " No arguments: source the current buffer content.
        call s:source_buffer(a:optional)
        return
    endif

    let target = a:1
    let opts = {}
    let optional = a:optional
    if a:0 == 2
        " Normalize CLI string arguments into a typed Dictionary.
        let opts = s:normalize_cmd_opts(a:2)
        let optional = get(opts, 'optional', 0) || a:optional
    endif

    if type(target) == v:t_list
        call s:source_list(target, optional, opts)
    else
        call s:source_target(target, optional, opts)
    endif
endfunction


function! src#(...) abort
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
    call s:init_cfg()

    if a:0 == 0
        " Default to current buffer if no target is provided.
        return s:source_buffer(0)
    endif

    let target = a:1
    let optional = get(a:, 2, 0)

    " Branch based on target type for fixed-arity core calls.
    if type(target) == v:t_list
        return s:source_list(target, optional, {})
    endif

    return s:source_target(target, optional, {})
endfunction


function! src#begin(...) abort
    " Push a base-directory scope onto the resolution stack.
    "
    " Args:
    " - [base_dir] (str): Absolute path or relative path resolved against
    "   the current active scope. Omit for default base directory.
    " - [opts] (dict): Optional Dict. Only follow_links is supported.
    "
    " Throws:
    " - src: invalid argument: unexpected argument count
    " - src: resolution failure: <PATH> not found
    "
    " Examples:
    "   call src#begin()
    "   call src#begin('~/.vim/vimrcs')
    "   call src#begin('configs')
    "   call src#begin('~/cfg-link', { 'follow_links': 0 })
    "
    call src#init()

    if a:0 == 0
        return s:begin_default({})
    endif

    if a:0 == 1
        return s:begin_explicit(a:1, {})
    endif

    if a:0 == 2
        return s:begin_explicit(a:1, s:normalize_begin_opts(a:2))
    endif

    call s:throw(g:src#ERR_INVALID_ARG, 'unexpected argument count')
endfunction


function! src#end() abort
    " Pop one base-directory scope from the stack. No-op when already empty.

    call s:init_cfg()
    call s:end()
endfunction


" }}}
" ==============================================================================
"  Sourcing & Scope {{{
" ==============================================================================

function! s:source_buffer(optional) abort
    " Source the contents of the current buffer.
    "
    " Args:
    " - optional (int): Non-zero to suppress errors.
    "
    " Throws:
    " - src: source failure: current buffer ...
    "
    let context = s:current_buffer_failure_context()
    try
        let path = expand('%:p')
        if bufname('%') !=# '' && filereadable(path) && !&modified
            " Source from disk if buffer is unchanged;
            call s:source_script(path, fnamemodify(path, ':p:h'), context, s:current_options())
        else
            " otherwise, source from memory via temp file.
            call s:source_buffer_contents(s:buffer_context_dir(), context, s:current_options())
        endif
    catch
        if v:exception =~# '^src:'
            throw v:exception
        endif
        call s:error(context, v:exception)
        call s:throw(g:src#ERR_SOURCE, context)
    endtry
endfunction


function! s:source_target(target, optional, opts) abort
    " Entry point for sourcing a specific logical target string.
    "
    " Args:
    " - target (str): Logical target to resolve and source.
    " - optional (int): Non-zero to skip if unreadable.
    " - opts (dict): Execution options.
    "
    call s:source(a:target, a:optional, a:opts)
endfunction


function! s:source_list(targets, optional, opts) abort
    " Entry point for sourcing a list of logical targets.
    "
    " Args:
    " - targets (str[]): List of targets to be sourced.
    " - optional (int): Non-zero to skip if unreadable.
    " - opts (dict): Execution options.
    "
    for target in a:targets
        call s:source(target, a:optional, a:opts)
    endfor
endfunction


function! s:begin_default(opts) abort
    " Push default base directory scope.
    "
    " Args:
    " - opts (dict): Scope options.
    "
    let base = s:resolve_default_dir()
    call s:begin_with_base(base, a:opts)
endfunction


function! s:begin_explicit(path, opts) abort
    " Push explicit path scope.
    "
    " Args:
    " - path (str): Base directory path.
    " - opts (dict): Scope options.
    "
    let base = s:resolve_explicit_base_dir(a:path)
    call s:begin_with_base(base, a:opts)
endfunction


function! s:end() abort
    " Pop the top base directory from the stack.

    if empty(s:ctx_stack)
        return
    endif

    call s:debug('end: ' .. s:ctx_stack[-1].dir)
    call remove(s:ctx_stack, -1)
endfunction


function! s:begin_with_base(base, opts) abort
    " Core logic for base directory scope activation.
    let follow_links = s:begin_follow_links(a:opts)
    let dir = follow_links ? s:realpath(a:base) : a:base
    call s:debug('begin: ' .. dir)
    call s:push_ctx(dir, 'scope', {'follow_links': follow_links})
endfunction


function! s:source(path, optional, opts) abort
    " Internal dispatcher for sourcing a file or directory.
    "
    " Args:
    " - path (str): Target path.
    " - optional (int): Non-zero to skip if invalid.
    " - opts (dict): Execution options.
    "
    " Throws:
    " - src: invalid target: source target <PATH> not found
    " - src: invalid target: file <PATH> is unreadable
    " - src: invalid target: directory <PATH> is unreadable
    "
    "
    if !s:call_enabled(a:opts)
        return
    endif

    let opts = s:effective_options(a:opts)
    let target = s:resolve_target_info(s:target_entry_path(a:path), opts)

    call s:debug('source: ' .. target.path)

    if target.kind ==# 'file'
        if !filereadable(target.path)
            if a:optional
                return
            endif
            call s:throw(g:src#ERR_INVALID_TARGET, 'file ' .. a:path .. ' is unreadable')
        endif
        call s:source_file(target.path, opts)

    elseif target.kind ==# 'dir'
        try
            call s:source_dir(target.path, opts)
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


function! s:source_file(path, opts) abort
    " Source a single Vimscript file.
    call s:source_script(a:path, fnamemodify(a:path, ':p:h'), a:path, a:opts)
endfunction


function! s:source_dir(path, opts) abort
    " Source all direct *.vim children of a directory.
    "
    " Args:
    " - path (str): Directory path.
    " - opts (dict): Execution options.
    "
    let stack_depth = len(s:ctx_stack)
    let children = s:dir_vim_children(a:path, a:opts)
    call s:push_ctx(a:path, 'source', a:opts)
    try
        for child in children
            call s:source_file(child.path, a:opts)
        endfor
    finally
        call s:restore_stack_depth(stack_depth)
    endtry
endfunction


function! s:source_script(path, context_dir, failure_context, opts) abort
    " Low-level helper to source a path with a given context.
    "
    " Args:
    " - path (str): Path to source.
    " - context_dir (str): Directory for scope push.
    " - failure_context (str): Diagnostic string.
    " - opts (dict): Execution options.
    "
    " Throws:
    " - src: source failure: <ERROR_MSG>
    "
    let stack_depth = len(s:ctx_stack)
    if !empty(a:context_dir) && !s:ctx_matches(a:context_dir, a:opts)
        call s:push_ctx(a:context_dir, 'source', a:opts)
    endif

    try
        execute 'source ' .. s:escape_source_path(a:path)
    catch
        call s:error(a:failure_context, v:exception)
        call s:throw(g:src#ERR_SOURCE, a:failure_context)
    finally
        call s:restore_stack_depth(stack_depth)
    endtry
endfunction


function! s:source_buffer_contents(context_dir, failure_context, opts) abort
    " Write buffer contents to a temporary file and source it.

    let tmp = tempname() .. '.vim'
    call writefile(getline(1, '$'), tmp)
    try
        call s:source_script(tmp, a:context_dir, a:failure_context, a:opts)
    finally
        call delete(tmp)
    endtry
endfunction


function! s:buffer_context_dir() abort
    " Determine the directory context for the current buffer.

    let path = expand('%:p')
    if empty(path)
        return ''
    endif

    return fnamemodify(path, ':p:h')
endfunction


function! s:current_buffer_failure_context() abort
    " Generate a diagnostic string for buffer source failures.

    let path = expand('%:p')
    if empty(path)
        return 'current buffer'
    endif

    return 'current buffer: ' .. path
endfunction


function! s:restore_stack_depth(depth) abort
    " Restore the context stack to a specific depth.

    while len(s:ctx_stack) > a:depth
        call remove(s:ctx_stack, -1)
    endwhile
endfunction


function! s:escape_source_path(path) abort
    " Escape a file path for use with the :source command.
    "
    " Args:
    " - path (str): Raw file path.
    "
    " Returns:
    "   str: Escaped path.
    "
    return fnameescape(a:path)
endfunction


function! s:target_entry_path(path) abort
    " Resolve a target path relative to the current context.
    "
    " Args:
    " - path (str): Relative or absolute target path.
    "
    " Returns:
    "   str: Expanded absolute path.
    "
    let expanded = s:expand_tilde(a:path)
    if s:is_abs_path(expanded)
        return expanded
    endif

    " Resolve relative to current stack top.
    return s:join_path(s:current_resolution_base(), expanded)
endfunction


function! s:current_resolution_base() abort
    " Identify the current base directory for path resolution.
    "
    " Returns:
    "   str: Absolute base path.
    "
    if !empty(s:ctx_stack)
        return s:ctx_stack[-1].dir
    endif

    return s:resolve_default_dir()
endfunction


function! s:resolve_explicit_base_dir(path) abort
    " Resolve and validate an explicit base directory.
    "
    " Args:
    " - path (str): Candidate path.
    "
    " Returns:
    "   str: Validated absolute path.
    "
    let expanded = s:expand_tilde(a:path)
    if s:is_abs_path(expanded)
        return s:require_dir(expanded)
    endif

    return s:require_dir(s:join_path(s:current_resolution_base(), expanded))
endfunction


function! s:dir_vim_children(path, opts) abort
    " Find all *.vim files in a directory, following links if configured.
    "
    " Args:
    " - path (str): Directory path.
    " - opts (dict): Execution options.
    "
    " Returns:
    "   dict[]: Loadable child target info entries.
    "
    " Throws:
    " - src: invalid target: directory <PATH> is unreadable
    "
    try
        let names = readdir(a:path, {n -> n !~# '^\.'})
    catch
        call s:throw(g:src#ERR_INVALID_TARGET, 'directory ' .. a:path .. ' is unreadable')
    endtry
    if empty(names) && s:looks_unreadable_dir(a:path)
        call s:throw(g:src#ERR_INVALID_TARGET, 'directory ' .. a:path .. ' is unreadable')
    endif

    let children = []
    for name in names
        let full = s:join_path(a:path, name)
        let target = s:resolve_target_info(full, a:opts)
        if target.kind ==# 'file' && name =~# '\.vim$'
            call add(children, target)
        endif
    endfor

    return sort(children, function('s:compare_target_basenames'))
endfunction


function! s:compare_target_basenames(a, b) abort
    " Compare two classified targets by their directory-entry basenames.
    let ba = fnamemodify(a:a.entry_path, ':t')
    let bb = fnamemodify(a:b.entry_path, ':t')
    return ba <# bb ? -1 : ba ># bb ? 1 : 0
endfunction


function! s:looks_unreadable_dir(path) abort
    " Best-effort probe for directories that some runtimes expose as empty
    " instead of raising from readdir().
    if !isdirectory(a:path) || !exists('*getfperm')
        return 0
    endif

    let perms = getfperm(a:path)
    if empty(perms) || strlen(perms) < 3
        return 0
    endif

    " Directory listing requires read + execute permission for the effective
    " user. We treat a missing owner read/execute bit as unreadable here.
    return strpart(perms, 0, 1) !=# 'r' || strpart(perms, 2, 1) !=# 'x'
endfunction


function! s:resolve_target_info(path, opts) abort
    " Classify a concrete path as a file, directory, or missing target.
    "
    " Args:
    " - path (str): Concrete absolute or relative path to inspect.
    " - opts (dict): Execution options.
    "
    " Returns:
    "   dict: Classified target info with resolved path and final filetype.
    "
    let info = {
          \ 'kind': 'missing',
          \ 'entry_path': a:path,
          \ 'path': a:path,
          \ 'ftype': '',
          \ }
    let follow_links = get(a:opts, 'follow_links', 0)
    let ftype = getftype(a:path)

    if ftype ==# 'link'
        if !follow_links
            let info.ftype = ftype
            return info
        endif

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


function! s:current_options() abort
    " Resolve the effective options for the current context.
    "
    " Returns:
    "   dict: Options dictionary.
    "
    if !empty(s:ctx_stack)
        return copy(s:ctx_stack[-1].options)
    endif

    return s:global_options()
endfunction


function! s:effective_options(opts) abort
    " Merge current context options with per-call overrides.
    "
    " Args:
    " - opts (dict): Per-call options.
    "
    " Returns:
    "   dict: Merged options dictionary.
    "
    let effective = s:current_options()
    if type(a:opts) == v:t_dict
        for key in s:EFFECTIVE_OPTION_KEYS
            if has_key(a:opts, key)
                let effective[key] = a:opts[key] != 0
            endif
        endfor
    endif

    return effective
endfunction


function! s:new_ctx(dir, kind, options) abort
    " Create a new context object.

    return {
          \ 'dir': a:dir,
          \ 'kind': a:kind,
          \ 'options': copy(a:options),
          \ }
endfunction


function! s:ctx_matches(dir, opts) abort
    " Check if a directory and options match the current context.

    if empty(s:ctx_stack)
        return 0
    endif

    let ctx = s:ctx_stack[-1]
    return ctx.dir ==# a:dir
          \ && get(ctx.options, 'follow_links', 0) ==# get(a:opts, 'follow_links', 0)
endfunction


function! s:call_enabled(opts) abort
    " Check if an execution is gated by an 'if' option.

    if type(a:opts) == v:t_dict && has_key(a:opts, 'if')
        return a:opts.if != 0
    endif

    return 1
endfunction


function! s:begin_follow_links(opts) abort
    " Determine the follow_links policy for a new scope.

    if type(a:opts) == v:t_dict && has_key(a:opts, 'follow_links')
        return a:opts.follow_links != 0
    endif

    return get(s:current_options(), 'follow_links', s:get_follow_links_cfg())
endfunction


function! s:global_options() abort
    " Resolve global configuration options.
    "
    " Returns:
    "   dict: Global options dictionary.
    "
    let opts = {'follow_links': s:get_follow_links_cfg()}
    return opts
endfunction


function! s:push_ctx(dir, kind, options) abort
    " Push a new context onto the stack.
    call add(s:ctx_stack, s:new_ctx(a:dir, a:kind, a:options))
endfunction


" }}}
" ==============================================================================
"  Base Directory Resolution {{{
" ==============================================================================

function! s:resolve_default_dir() abort
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
    let cache_key = s:default_dir_cache_key()
    if s:default_dir_cache_key ==# cache_key && !empty(s:default_dir_cache_value)
        return s:default_dir_cache_value
    endif

    let base_dir = s:get_base_dir_cfg()
    if !empty(base_dir)
        let path = s:expand_tilde(base_dir)
        if !s:is_abs_path(path)
            call s:throw(
                \ g:src#ERR_RESOLUTION,
                \ 'path must be absolute: ' .. path
                \ )
        endif

        let base_dir = s:require_dir(path)
        call s:debug('default_base_dir: ' .. base_dir)
        let s:default_dir_cache_key = cache_key
        let s:default_dir_cache_value = base_dir
        return base_dir
    endif

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

    let base_dir = s:normalize_path(base_dir)
    if !isdirectory(base_dir)
        call s:throw(
            \ g:src#ERR_RESOLUTION,
            \ 'base directory not found: ' .. base_dir
            \ )
    endif

    call s:debug('default_base_dir: ' .. base_dir)
    let s:default_dir_cache_key = cache_key
    let s:default_dir_cache_value = base_dir
    return base_dir
endfunction


function! s:xdg_config_home() abort
    " Return the normalized XDG config home directory.

    if !empty($XDG_CONFIG_HOME)
        return s:normalize_path($XDG_CONFIG_HOME)
    endif

    return s:normalize_path(s:home_dir() .. '/.config')
endfunction


function! s:dir_if_exists(path) abort
    " Return the path when it exists as a directory; otherwise return an empty
    " string.

    if isdirectory(a:path)
        return a:path
    endif

    return ''
endfunction


function! s:resolve_base_dir_with_name(base_name) abort
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


function! s:resolve_base_dir_without_name() abort
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


function! s:default_dir_cache_key() abort
    " Build the cache key for default base-directory resolution.
    return string([s:get_base_dir_cfg(), s:get_base_name_cfg()])
endfunction


" }}}
" ==============================================================================
"  Configuration {{{
" ==============================================================================

function! s:init_cfg() abort
    " Ensure the g:src namespace is correctly initialized as a Dictionary.

    if !exists('g:src') || type(g:src) != v:t_dict
        let g:src = {}
    endif
endfunction


function! s:get_cfg(key, default) abort
    " Get a configuration value from the g:src namespace with a fallback.
    "
    " Args:
    " - key (str): Configuration key string.
    " - default (any): Fallback value if the key is missing.
    "
    " Returns:
    "   any: The configured value or the provided default.
    "
    " Throws:
    " - src: invalid state: g:src must be a Dictionary
    "
    if exists('g:src') && type(g:src) != v:t_dict
        call s:throw(
            \ g:src#ERR_INVALID_STATE,
            \ 'g:src must be a Dictionary'
            \ )
    endif

    return get(g:, 'src', {})->get(a:key, a:default)
endfunction


function! s:get_base_dir_cfg() abort
    " Get the configured explicit base directory override.
    return s:get_cfg('base_dir', s:DEFAULT_BASE_DIR)
endfunction


function! s:get_base_name_cfg() abort
    " Get the configured named base directory token.
    return s:get_cfg('base_name', s:DEFAULT_BASE_NAME)
endfunction


function! s:get_follow_links_cfg() abort
    " Get the global follow_links policy.
    return s:get_cfg('follow_links', s:DEFAULT_FOLLOW_LINKS) != 0
endfunction


function! s:get_def_commands_cfg() abort
    " Check if automatic command definition is enabled.
    return s:get_cfg('def_commands', s:DEFAULT_DEF_COMMANDS) != 0
endfunction


function! s:get_debug_cfg() abort
    " Check if debug logging is enabled.
    return s:get_cfg('debug', s:DEFAULT_DEBUG) != 0
endfunction


" }}}
" ==============================================================================
"  Diagnostic {{{
" ==============================================================================

function! s:throw(kind, detail) abort
    " Throw a standardized library error following the project contract.
    "
    " Args:
    " - kind (str): Error category (e.g., g:src#ERR_INVALID_ARG).
    " - detail (str): Specific failure description.
    "
    throw 'src: ' .. a:kind .. ': ' .. a:detail
endfunction


function! s:error(context, exception) abort
    " Print a formatted failure report to the user messages.
    "
    " Args:
    " - context (str): Diagnostic string describing where it failed.
    " - exception (str): The original raw exception message.
    "
    echohl ErrorMsg
    echomsg '[vim-src] source failed: ' .. a:context
    echomsg '[vim-src] original error: ' .. a:exception
    echohl None
endfunction


function! s:debug(msg) abort
    " Print a debug message if logging is enabled in configuration.
    "
    " Args:
    " - msg (str): Message text to log.
    "
    if s:get_debug_cfg()
        echomsg '[vim-src] ' .. a:msg
    endif
endfunction


" }}}
" ==============================================================================
"  Path {{{
" ==============================================================================

if s:IS_WINDOWS
    function! s:is_abs_path(path) abort
        " Check if a path is absolute on Windows.
        return a:path =~# '^[A-Za-z]:[/\\]'
            \ || a:path =~# '^[/\\][/\\]'
            \ || a:path =~# '^[\/\\]'
    endfunction
else
    function! s:is_abs_path(path) abort
        " Check if a path is absolute on Unix-like systems.
        return a:path[0:0] ==# '/'
    endfunction
endif


function! s:join_path(base, child) abort
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
    return substitute(a:base, '[/\\]\+$', '', '') .. '/' .. a:child
endfunction


function! s:expand_tilde(path) abort
    " Robustly expand ~ prefix without triggering environment expansion.
    "
    " Args:
    " - path (str): Path string potentially containing ~.
    "
    " Returns:
    "   str: Path with ~ expanded to home directory.
    "
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


function! s:normalize_path(path) abort
    " Normalize a path to its absolute simplified form.
    "
    " Args:
    " - path (str): Path string.
    "
    " Returns:
    "   str: Normalized absolute path.
    "
    return fnamemodify(a:path, ':p')
endfunction


function! s:realpath(path) abort
    " Resolve symbolic links and ensure the result is a valid absolute path.
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
    let resolved = resolve(a:path)
    if !s:is_abs_path(resolved)
        call s:throw(g:src#ERR_RESOLUTION, 'path must be absolute: ' .. resolved)
    endif

    return s:require_dir(resolved)
endfunction


function! s:require_dir(path) abort
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

function! s:normalize_cmd_opts(opts) abort
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
    if type(a:opts) != v:t_dict
        call s:throw(g:src#ERR_INVALID_ARG, 'opts must be a Dictionary')
    endif

    return s:normalize_opts(a:opts, s:CMD_OPTION_KEYS, s:CMD_BOOL_OPTION_KEYS)
endfunction


function! s:normalize_begin_opts(opts) abort
    " Ensure scope options are valid and typed correctly.
    "
    " Args:
    " - opts (dict): Scope options.
    "
    " Returns:
    "   dict: Normalized options.
    "
    " Throws:
    " - src: invalid argument: opts must be a Dictionary
    " - src: invalid argument: unsupported option: ...
    "
    if type(a:opts) != v:t_dict
        call s:throw(g:src#ERR_INVALID_ARG, 'opts must be a Dictionary')
    endif

    return s:normalize_opts(a:opts, s:BEGIN_OPTION_KEYS, s:BEGIN_BOOL_OPTION_KEYS)
endfunction


function! s:normalize_opts(opts, allowed_keys, bool_keys) abort
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
    let opts = {}
    for key in keys(a:opts)
        if index(a:allowed_keys, key) < 0
            call s:throw(g:src#ERR_INVALID_ARG, 'unsupported option: ' .. key)
        endif
        let opts[key] = a:opts[key]
    endfor

    for key in a:bool_keys
        if has_key(opts, key)
            let opts[key] = opts[key] != 0
        endif
    endfor

    return opts
endfunction


" }}}
" ==============================================================================
"  Misc Helpers {{{
" ==============================================================================

function! s:commands_ready() abort
    " Check if the :Src command is defined and registered.
    return s:commands_defined && exists(':Src') == 2
endfunction


function! s:home_dir() abort
    " Return the home directory as a literal path, preferring $HOME.

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
