filetype plugin indent on

let mapleader=" "

set background=dark
set cindent
set expandtab ts=4 sw=4 ai
set listchars=eol:¬,tab:>·,trail:~,extends:>,precedes:<,space:␣
set number

call plug#begin('~/.vim/plugged')
  Plug 'jiangmiao/auto-pairs'
  Plug 'tpope/vim-surround'
  Plug 'github/copilot.vim'
  Plug 'ms-jpq/chadtree', {'branch': 'chad', 'do': 'python3 -m chadtree deps'}
call plug#end()

augroup numbertoggle
  autocmd!
  autocmd BufEnter,FocusGained,InsertLeave,WinEnter * if &nu && mode() != "i" | set rnu   | endif
  autocmd BufLeave,FocusLost,InsertEnter,WinLeave   * if &nu                  | set nornu | endif
augroup END

nnoremap <F22>     :w<Enter>:! %:p<Enter>
nnoremap <Leader>1 :CHADopen<Enter>
nnoremap <C-E>     :buffers<CR>:buffer<Space>
