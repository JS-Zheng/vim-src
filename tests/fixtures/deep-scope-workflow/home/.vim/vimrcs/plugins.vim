let g:deep_scope_workflow_hits = get(g:, 'deep_scope_workflow_hits', [])
call add(g:deep_scope_workflow_hits, 'plugins-enter')
call src#begin('my-plugins')
Src 'fzf.vim'
Src 'coc.vim'
call src#end()
call add(g:deep_scope_workflow_hits, 'plugins-after')
