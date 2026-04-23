let g:multi_layer_workflow_hits = get(g:, 'multi_layer_workflow_hits', [])
call src#begin('scoped')
Src '10-parent.vim'
call src#end()
