let g:multi_layer_workflow_hits = get(g:, 'multi_layer_workflow_hits', [])
call add(g:multi_layer_workflow_hits, '20-child')
call src#begin('grand')
Src '30-grandchild.vim'
call src#end()
Src '40-after-grandchild.vim'
