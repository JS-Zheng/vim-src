let g:deep_scope_workflow_hits = get(g:, 'deep_scope_workflow_hits', [])
call add(g:deep_scope_workflow_hits, 'rg-enter')
call src#begin('~/.local/opt/rg')
Src '~/.vim/vimrcs/rg.config.vim'
call src#($HOME . '/.vim/vimrcs/rg.plugin.vim')
Src 'benchmark.vim'
call src#end()
Src 'after-rg.vim'
