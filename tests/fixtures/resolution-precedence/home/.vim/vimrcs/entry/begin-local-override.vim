let g:src_resolution_precedence_hits += ['entry-begin-local-override']
call src#begin('../child')
try
  Src 'shared.vim'
finally
  call src#end()
endtry
