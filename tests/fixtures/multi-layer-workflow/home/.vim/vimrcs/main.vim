let g:multi_layer_workflow_hits = get(g:, 'multi_layer_workflow_hits', [])
call add(g:multi_layer_workflow_hits, 'main-start')
Src 'leaf-top.vim'
call src#begin('layers')
Src '10-layer-root.vim'
call src#end()
call add(g:multi_layer_workflow_hits, 'main-end')
