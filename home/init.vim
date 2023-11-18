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
autocmd TermOpen * setlocal statusline=%{b:term_title}

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
  let b:term_title = a:name . ' (' . bufname('%') . ')'
endfunction

command! -nargs=1 RenameTerminalBuffer :call s:rename_terminal_buffer(<q-args>)
nmap <leader>tr :RenameTerminalBuffer<space>

command! -nargs=0 CreateGitTerminalBuffer :call s:create_named_terminal_buffer('git')
nmap <leader>tg :CreateGitTerminalBuffer<CR>

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" FZF Shortcuts                                                                "
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Quickly switch tabs with fzf
if !exists('g:fzf_tabs_mru')
  let g:fzf_tabs_mru = {}
endif
augroup fzf_tabs
  autocmd!
  autocmd TabEnter * let g:fzf_tabs_mru[tabpagenr()] = localtime()
  autocmd TabClosed * silent! call remove(g:fzf_tabs_mru, expand('<afile>'))
augroup END

function! s:fzf_tab_sink(line)
  let list = matchlist(a:line, '^\[\([0-9]\+\)\]')
  let tabnr = list[1]
  execute tabnr . 'tabnext'
endfunction

function! s:sort_tabs_mru(...)
  let [t1, t2] = map(copy(a:000), 'get(g:fzf_tabs_mru, v:val, v:val)')
  return t1 - t2
endfunction

function! s:fzf_list_tabs(...)
  let l:tabs = []
  let l:longest_tab_number_length = 0
  let l:longest_name_length = 0

  for t in sort(range(1, tabpagenr('$')), 's:sort_tabs_mru')
    let tab_number = printf("[%d]", t)
    let pwd = getcwd(-1, t)
    let name = fnamemodify(pwd, ':t')

    let l:tab_number_length = len(l:tab_number)
    if l:tab_number_length > l:longest_tab_number_length
      let l:longest_tab_number_length = l:tab_number_length
    endif

    let l:name_length = len(l:name)
    if l:name_length > l:longest_name_length
      let l:longest_name_length = l:name_length
    endif

    let tab = {
      \ 'tab_number' : tab_number,
      \ 'directory_path' : fnamemodify(pwd, ':p:~'),
      \ 'directory_name' : name,
      \ }
    call add(l:tabs, tab)
  endfor

  let lines = []
  let l:format = "%-" . l:longest_tab_number_length . "S %-" . l:longest_name_length . "S %s"
  for tab in l:tabs
    let line = printf(l:format, tab['tab_number'], tab['directory_name'], tab['directory_path'])
    call add(lines, line)
  endfor

  return fzf#run({
  \ 'source': reverse(lines),
  \ 'sink': function('s:fzf_tab_sink'),
  \ 'down': '30%',
  \ 'options': ['--header-lines=1']
  \})
endfunction

command! -nargs=0 FzfTabs :call s:fzf_list_tabs()

" Key mappings for fzf plugin
nmap <leader>f :FzfGFiles<CR>
nmap <leader>tt :FzfFiles<CR>
nmap <leader>bb :FzfBuffers<CR>
nmap <leader>c :FzfHistory:<CR>
nmap <leader>gt :FzfTabs<CR>
nmap <leader>gp :FzfSwitchProject<CR>

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Logbook management                                                           "
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

function! s:logbook_new(name)
  let l:basename = strftime('%Y-%m-%d') . '-' . a:name . '.md'
  let l:fname = fnamemodify("~/workspace/cjlarose/logbook/picktrace/" . l:basename, ":p")
  execute "e " . l:fname
endfunction

command! -nargs=1 LogbookNew :call s:logbook_new(<q-args>)

function! s:logbook_list()
  execute 'FzfFiles ' . fnamemodify("~/workspace/cjlarose/logbook/", ":p")
endfunction

command! -nargs=0 LogbookList :call s:logbook_list()

" Key maps
nmap <leader>bn :LogbookNew<space>
nmap <leader>bl :LogbookList<CR>
