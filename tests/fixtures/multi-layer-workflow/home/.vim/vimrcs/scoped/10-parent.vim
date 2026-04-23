let g:multi_layer_workflow_hits = get(g:, 'multi_layer_workflow_hits', [])
call add(g:multi_layer_workflow_hits, '10-parent')
call src#begin('child')
Src '20-child.vim'
call src#end()
Src '50-after-child.vim'
