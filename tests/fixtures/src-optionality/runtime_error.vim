let g:src_optionality_hits = add(get(g:, 'src_optionality_hits', []), 'runtime-before-error')
throw 'boom from readable script'
