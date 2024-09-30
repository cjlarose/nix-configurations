{ pkgs, ... }: {

  programs.neovim = {
    enable = true;
    withPython3 = false;
    withRuby = false;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;
    plugins = with pkgs.vimPlugins; [
      omnisharpVim
      vim-commentary
      vim-sensible
      vim-nix
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
          let g:fzfSwitchProjectWorkspaces = [ '~/workspace', '~/go/src' ]
          let g:fzfSwitchProjectProjectDepth = 2
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
    ];
    extraConfig = builtins.readFile ./init.vim;
  };

}
