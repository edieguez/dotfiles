filetype plugin indent on

set background=dark
set cindent
set expandtab ts=4 sw=4 ai
set listchars=eol:¬,tab:>·,trail:~,extends:>,precedes:<,space:␣
set number

call plug#begin('~/.vim/plugged')
  Plug 'jiangmiao/auto-pairs'
  Plug 'tpope/vim-surround'
  Plug 'github/copilot.vim'
call plug#end()

augroup numbertoggle
  autocmd!
  autocmd BufEnter,FocusGained,InsertLeave,WinEnter * if &nu && mode() != "i" | set rnu   | endif
  autocmd BufLeave,FocusLost,InsertEnter,WinLeave   * if &nu                  | set nornu | endif
augroup END
