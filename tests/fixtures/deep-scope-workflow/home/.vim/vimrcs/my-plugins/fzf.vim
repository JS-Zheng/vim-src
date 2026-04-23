let g:deep_scope_workflow_hits = get(g:, 'deep_scope_workflow_hits', [])
call add(g:deep_scope_workflow_hits, 'fzf-enter')
call src#begin('~/.local/opt/fzf')
Src 'vim/coc-fzf.vim'
Src 'vim/fzf-grep.vim'
call src#end()
Src 'after-fzf.vim'
