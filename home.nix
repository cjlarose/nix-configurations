{ pkgs, fzfVim, ... }: {
  imports = [ ./personal-scripts.nix ];

  home.sessionVariables = {
    EDITOR = "nvr-edit-in-split-window";
    LESS = "--quit-if-one-screen --RAW-CONTROL-CHARS --no-init";
  };

  home.packages = [
    pkgs.neovim-remote
  ];

  home.shellAliases = {
    gs = "git status";
  };

  programs.zsh = {
    enable = true;
    initExtra = ''
      # Prompt
      setopt prompt_subst
      . ${pkgs.git}/share/git/contrib/completion/git-prompt.sh
      PROMPT='%~ %F{green}$(__git_ps1 "%s ")%f$ '

      # Allow command line editing in an external editor
      autoload -Uz edit-command-line
      zle -N edit-command-line
      bindkey '^x^e' edit-command-line
    '';
  };

  programs.git = {
    enable = true;
    userName = "Chris LaRose";
    userEmail = "cjlarose@gmail.com";
    extraConfig = {
      color.ui = true;
      rebase.autosquash = true;
      commit.verbose = true;
      pull.ff = "only";
    };
    ignores = [
      "[._]*.s[a-w][a-z]"
      "[._]s[a-w][a-z]"
    ];
  };

  programs.ssh = {
    enable = true;
    extraOptionOverrides = {
      AddKeysToAgent = "yes";
    };
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    plugins = with pkgs.vimPlugins; [
      vim-sensible
      vim-nix
      {
        plugin = onedark-vim;
        config = ''
          " Enable 24-bit/true color
          set termguicolors

          colorscheme onedark
        '';
      }
      {
        plugin = fzfVim.defaultPackage."${self.system}";
        config = ''
          " set prefix for FZF functions
          let g:fzf_command_prefix = 'Fzf'

          " disable fzf preview
          let g:fzf_preview_window = []
        '';
      }
      vim-fugitive
      vim-rhubarb
      vim-fubitive
    ];
    extraConfig = ''
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

      " Create a new tab using fzf
      let g:fzfSwitchProjectWorkspaces = [ '~/workspace', '~/workspace/cjlarose/dotfiles' ]
      let g:fzfSwitchProjectProjectDepth = 2

      let s:workspaces = get(g:, 'fzfSwitchProjectWorkspaces', [])
      let s:projects = get(g:, 'fzfSwitchProjectProjects', [])
      let s:gitInit = get(g:, 'fzfSwitchProjectGitInitBehavior', 'ask')
      let s:chooseFile = get(g:, 'fzfSwitchProjectAlwaysChooseFile', 1)
      let s:projectDepth = get(g:, 'fzfSwitchProjectProjectDepth', 1)

      function! s:fzf_list_projects()
        let l:projects = s:getAllDirsFromWorkspaces(s:workspaces, 1)
        let l:projects = l:projects + s:projects
        let l:opts = {
          \ 'sink': function('s:switchToProjectDir'),
          \ 'source': s:formatProjectList(l:projects),
          \ 'down': '40%'
          \ }
        call fzf#run(fzf#wrap(l:opts))
      endfunction

      function! s:switchToProjectDir(projectLine)
        try
          let autochdir = &autochdir
          set noautochdir
          let l:parts = matchlist(a:projectLine, '\(\S\+\)\s\+\(\S\+\)')
          let l:path = l:parts[2] . '/' . l:parts[1]
          execute 'tabnew'
          execute 'tcd' l:path
          if s:gitInit !=# 'none'
            call s:initGitRepoIfRequired(s:gitInit)
          endif
          execute 'CreateGitTerminalBuffer'
        finally
          let &autochdir = autochdir
        endtry
      endfunction

      function! s:getAllDirsFromWorkspaces(workspaces, depth)

        if len(a:workspaces) == 0
          return []
        endif

        let l:dirs = globpath(join(a:workspaces, ','), '*/', 1)

        let l:projectFolders = []
        let l:nonProjectFolders = []

        for dir in split(l:dirs, "\n")
          if FugitiveIsGitDir(dir . '/.git') || a:depth == s:projectDepth
            call add(l:projectFolders, fnamemodify(dir, ':h'))
          else
            call add(l:nonProjectFolders, fnamemodify(dir, ':h'))
          endif
        endfor

        return l:projectFolders + s:getAllDirsFromWorkspaces(l:nonProjectFolders, a:depth + 1)
      endfunction

      function! s:formatProjectList(dirs)
        let l:dirParts = [  ]
        let l:longest = 0
        for dir in a:dirs
          let l:name = fnamemodify(dir, ':t')
          let l:length = len(l:name)
          if l:length > l:longest
            let l:longest = l:length
          endif
          let dir = { 'name' : l:name, 'dir' : fnamemodify(dir, ':h') }
          call add(l:dirParts, dir)
        endfor
        return s:generateProjectListLines(l:dirParts, l:longest)
      endfunction

      function! s:generateProjectListLines(dirParts, longest)
        let l:outputLines = [  ]
        for dir in a:dirParts
          let l:padding = a:longest - len(dir['name'])
          let l:line = dir['name']
                \ . repeat(' ', l:padding)
                \ . ' ' . dir['dir']
          call add(l:outputLines, l:line)
        endfor
        return l:outputLines
      endfunction

      function! s:initGitRepoIfRequired(behaviour)
        if !FugitiveIsGitDir(getcwd() . '/.git')
          if a:behaviour ==# 'ask'
            let s:yesNo = input('Initialise git repository? (y/n) ')
          elseif a:behaviour ==# 'auto'
            let s:yesNo = 'yes'
          endif
          if s:yesNo ==? 'y' || s:yesNo ==? 'yes'
            !git init
          endif
        endif
      endfunction

      command! FzfSwitchProject :call s:fzf_list_projects()

      " Key mappings for fzf plugin
      nmap <leader>f :FzfGFiles<CR>
      nmap <leader>tt :FzfFiles<CR>
      nmap <leader>bb :FzfBuffers<CR>
      nmap <leader>c :FzfHistory:<CR>
      nmap <leader>gt :FzfTabs<CR>
      nmap <leader>gp :FzfSwitchProject<CR>
    '';
  };
}
