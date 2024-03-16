{ pkgs, ... }: {
  home.packages = [ pkgs.asdf-vm ];

  programs.zsh = {
    initExtra = ''
      if [ -d "${pkgs.asdf-vm}" ]; then
        source "${pkgs.asdf-vm}/share/asdf-vm/asdf.sh"
      fi
    '';
  };
}
