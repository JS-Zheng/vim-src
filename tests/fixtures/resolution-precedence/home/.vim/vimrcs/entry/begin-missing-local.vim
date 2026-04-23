let g:src_resolution_precedence_hits += ['entry-begin-missing-local']
call src#begin('../empty')
try
  Src 'shared.vim'
finally
  call src#end()
endtry
