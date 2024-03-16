{ pkgs, ... }: {
  home.packages = [
    pkgs.asdf-vm
    pkgs.libyaml # for installing ruby versions
  ];

  programs.zsh = {
    initExtra = ''
      if [ -d "${pkgs.asdf-vm}" ]; then
        source "${pkgs.asdf-vm}/share/asdf-vm/asdf.sh"
      fi
    '';
  };
}
