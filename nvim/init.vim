" Neovim config for vim-airline minimal style

" Plugin manager
call plug#begin('~/.local/share/nvim/plugged')
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
call plug#end()

" Visual tweaks
highlight LineNr ctermbg=none
highlight Normal ctermbg=none
highlight NonText ctermbg=none
highlight SignColumn ctermbg=none
highlight VertSplit ctermbg=none ctermfg=98 cterm=none

" Color column at 100 chars
set colorcolumn=100
highlight ColorColumn ctermbg=93

" Airline settings
let g:airline_theme='selenized_bw'
let g:airline#extensions#branch#enabled=1
let g:airline#extensions#hunks#enabled=0
let g:airline_powerline_fonts=1
let g:airline_detect_spell=0

let g:airline_mode_map = {
      \ '__'     : '-',
      \ 'c'      : 'C',
      \ 'i'      : 'I',
      \ 'ic'     : 'I',
      \ 'ix'     : 'I',
      \ 'n'      : 'N',
      \ 'multi'  : 'M',
      \ 'ni'     : 'N',
      \ 'no'     : 'N',
      \ 'R'      : 'R',
      \ 'Rv'     : 'R',
      \ 's'      : 'S',
      \ 'S'      : 'S',
      \ 't'      : 'T',
      \ 'v'      : 'V',
      \ 'V'      : 'V',
      \ }

