" Map leader key to ,
nnoremap <SPACE> <Nop>
let mapleader = " "

" Enable both relative number and number to turn on 'hybrid mode'
set relativenumber
set number

" Write spaces instead of tabs when hitting <tab>
set expandtab

" Write exactly 2 spaces when hitting <tab>
set tabstop=2

" Use 2 spaces for indentation
set shiftwidth=2

" Highlight search results
set hlsearch

" Map fd in insert mode to esc
inoremap fd <Esc>

" Map fd in terminal mode to return to normal mode
tnoremap fd <C-\><C-n>

" Switch between windows more easily
nmap <silent> <leader>h :wincmd h<CR>
nmap <silent> <leader>j :wincmd j<CR>
nmap <silent> <leader>k :wincmd k<CR>
nmap <silent> <leader>l :wincmd l<CR>
nmap <silent> <leader>o :wincmd o<CR>
nmap <silent> <leader>= :wincmd =<CR>

" Show whitespace characters (tabs, trailing spaces)
set list

" Use the system clipboard as the default register
set clipboard=unnamed

" Allow modified buffers to be hidden (except for netrw buffers)
" https://github.com/tpope/vim-vinegar/issues/13
set nohidden
augroup netrw_buf_hidden_fix
  autocmd!

  " Set all non-netrw buffers to bufhidden=hide
  autocmd BufWinEnter *
    \  if &ft != 'netrw'
    \|   set bufhidden=hide
    \| endif
augroup end

" Fix syntax highlighting for tsx files
au BufNewFile,BufRead *.tsx setlocal filetype=typescript.tsx

" Set the statusline of terminal buffers to the term title
autocmd TermOpen * setlocal statusline=%{get(b:,'display_name','')}\ %{b:term_title}

" Change indentation settings for kotlin files
autocmd Filetype kotlin setlocal tabstop=4 shiftwidth=4

" Disable scrolloff because it makes curses-like programs jump around in
" terminal buffers
" https://github.com/neovim/neovim/issues/11072
set scrolloff=0

" Never show tabline
set showtabline=0

" Clear search highlight
nmap <leader>n :nohlsearch<CR>

" Always display signcolumn
set signcolumn=yes

" Disable swap files
set noswapfile

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Terminal Buffer Shortcuts                                                    "
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:create_named_terminal_buffer(name, ...)
  let term_command = a:0 >= 1 ? a:000 : &shell
  enew
  call termopen(term_command, {'cwd': getcwd()})
  call s:rename_terminal_buffer(a:name)
endfunction

command! -nargs=+ CreateNamedShellTerminalBuffer :call s:create_named_terminal_buffer(<f-args>)
nmap <leader>tn :CreateNamedShellTerminalBuffer<space>

function! s:rename_terminal_buffer(name)
  let b:display_name = a:name
endfunction

command! -nargs=1 RenameTerminalBuffer :call s:rename_terminal_buffer(<q-args>)
nmap <leader>tr :RenameTerminalBuffer<space>

command! -nargs=0 CreateGitTerminalBuffer :call s:create_named_terminal_buffer('git')
nmap <leader>tg :CreateGitTerminalBuffer<CR>

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" vim-grepper configuration                                                    "
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

nnoremap <leader>gr :Grepper -tool rg<cr>
nnoremap <leader>* :Grepper -tool rg -cword -noprompt<cr>
