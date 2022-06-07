{ pkgs, ... }: {
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
    '';
  };
}
