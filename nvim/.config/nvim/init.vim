filetype plugin indent on

let mapleader=","

set background=dark
set expandtab ts=4 sw=4 ai
set listchars=eol:¬,tab:»·,trail:␣,extends:>,precedes:<,space:·
set number

call plug#begin('~/.vim/plugged')
  Plug 'jiangmiao/auto-pairs'
  Plug 'ms-jpq/chadtree', {'branch': 'chad', 'do': 'python3 -m chadtree deps'}
  Plug 'github/copilot.vim'
  Plug 'tpope/vim-surround'
  Plug 'luochen1990/rainbow'
call plug#end()

augroup numbertoggle
  autocmd!
  autocmd BufEnter,FocusGained,InsertLeave,WinEnter * if &nu && mode() != "i" | set rnu   | endif
  autocmd BufLeave,FocusLost,InsertEnter,WinLeave   * if &nu                  | set nornu | endif
augroup END

let g:rainbow_active = 1

" Reload VIM configuration
nnoremap <Leader>rv :so $MYVIMRC<Enter>
nnoremap <leader>ev :e $MYVIMRC<Enter>

" Run current file
nnoremap <F5> :w<Enter>:! %:p<Enter>
inoremap <F5> <Esc>:w<Enter>:! %:p<Enter>

" Save current file
nnoremap <C-S> :w<Enter>
inoremap <C-S> <Esc>:w<Enter>a

nnoremap <C-Q> :wq<Enter>
inoremap <C-Q> <Esc>:wq<Enter>

" Undo last change. Use <C-R> to redo
nnoremap <C-Z> u
inoremap <C-Z> <Esc>u

" New line
nnoremap <Leader><Enter> o
inoremap <Leader><Enter> <Esc>o

" IDE like mappings
nnoremap <Leader>1 :CHADopen<Enter>
nnoremap <C-E> :buffers<CR>:buffer<Space>
