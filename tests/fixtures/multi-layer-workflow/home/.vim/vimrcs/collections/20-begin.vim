let g:multi_layer_workflow_hits = get(g:, 'multi_layer_workflow_hits', [])
call add(g:multi_layer_workflow_hits, '20-collection-begin')
call src#begin('deep')
Src '21-deep.vim'
call src#end()
Src 'plain/22-after.vim'
