{ config, lib, pkgs, ... }:

let
  cfg = config.cjlarose.neovim;

  telescopeConfigRaw = builtins.readFile ./neovim/telescope-config.lua;
  workspacesLua = "{ " + builtins.concatStringsSep ", " (map (ws: "'${ws}'") cfg.projectWorkspaces) + " }";
  maxDepthLua = toString cfg.projectMaxDepth;
  telescopeConfig = builtins.replaceStrings ["__WORKSPACES__" "__MAX_DEPTH__"] [workspacesLua maxDepthLua] telescopeConfigRaw;
in {
  options.cjlarose.neovim = {
    projectWorkspaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "~/worktrees" ];
      description = "Workspace directories for the telescope project switcher";
    };
    projectMaxDepth = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Max directory depth when scanning for projects";
    };
  };

  config = {
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
        plenary-nvim
        {
          plugin = telescope-nvim;
          config = telescopeConfig;
          type = "lua";
        }
        vim-fugitive
        vim-rhubarb
        vim-fubitive
        diffview-nvim
        {
          plugin = nvim-lspconfig;
          config = builtins.readFile ./neovim/lsp-config.lua;
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
      extraConfig = builtins.readFile ./neovim/init.vim;
    };
  };
}
