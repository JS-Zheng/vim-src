let g:deep_scope_workflow_hits = get(g:, 'deep_scope_workflow_hits', [])
call add(g:deep_scope_workflow_hits, 'fzf-grep-enter')
call src#begin('grep-exts')
Src 'rg.vim'
Src 'ag.vim'
call src#end()
Src 'after-grep.vim'
