{ pkgs, ... }: {

  programs.neovim = {
    enable = true;
    withPython3 = false;
    withRuby = false;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    plugins = with pkgs.vimPlugins; [
      vim-commentary
      vim-sensible
      vim-nix
      kotlin-vim
      vim-python-pep8-indent
      vim-terraform
      {
        plugin = onedark-vim;
        config = ''
          " Enable 24-bit/true color
          set termguicolors

          colorscheme onedark
        '';
      }
      {
        plugin = fzf-vim;
        config = ''
          " set prefix for FZF functions
          let g:fzf_command_prefix = 'Fzf'

          " disable fzf preview
          let g:fzf_preview_window = []
        '';
      }
      {
        plugin = fzf-project;
        config = ''
          let g:fzfSwitchProjectWorkspaces = [ '~/worktrees', '~/workspace', '~/workspace/cjlarose/dotfiles' ]
          let g:fzfSwitchProjectProjectDepth = 3
        '';
      }
      vim-fugitive
      vim-rhubarb
      vim-fubitive
      {
        plugin = nvim-lspconfig;
        config = builtins.readFile ./lsp-config.lua;
        type = "lua";
      }
      vim-unimpaired
      vim-grepper
      {
        plugin = vim-prettier;
        config = ''
          let g:prettier#autoformat = 1
          let g:prettier#autoformat_require_pragma = 0
          let g:prettier#config#trailing_comma = 'all'
        '';
      }
      vim-surround
    ];
    extraConfig = builtins.readFile ./init.vim;
  };

}
