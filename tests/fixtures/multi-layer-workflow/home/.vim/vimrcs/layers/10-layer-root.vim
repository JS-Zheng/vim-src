let g:multi_layer_workflow_hits = get(g:, 'multi_layer_workflow_hits', [])
call add(g:multi_layer_workflow_hits, '10-layer-root')
Src '15-child-no-begin.vim'
call src#begin('deeper')
Src '20-deeper.vim'
call src#end()
Src '30-after-deeper.vim'
