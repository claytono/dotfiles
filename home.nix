{ config, pkgs, lib, ... }:

let
  # Custom package to include only the watch binary from procps on macOS
  watch-only = pkgs.stdenv.mkDerivation {
    name = "watch-only";
    unpackPhase = "true";
    buildPhase = "true";
    installPhase = ''
      mkdir -p $out/bin
      cp ${pkgs.procps}/bin/watch $out/bin/
    '';
    meta = with pkgs.lib; {
      description = "Only the watch binary from procps for macOS";
      platforms = platforms.darwin;
    };
  };

  # Custom package to include only specific binaries from coreutils and findutils
  coreutils-partial = pkgs.stdenv.mkDerivation {
    name = "coreutils-partial";
    unpackPhase = "true";
    buildPhase = "true";
    installPhase = ''
      mkdir -p $out/bin
      cp ${pkgs.coreutils}/bin/timeout $out/bin/
      cp ${pkgs.findutils}/bin/find $out/bin/
    '';
    meta = with pkgs.lib; {
      description = "Only timeout from coreutils and find from findutils";
      platforms = platforms.darwin;
    };
  };

  # Custom package to include only the ts binary from moreutils
  ts-only = pkgs.stdenv.mkDerivation {
    name = "ts-only";
    unpackPhase = "true";
    buildPhase = "true";
    installPhase = ''
      mkdir -p $out/bin
      cp ${pkgs.moreutils}/bin/ts $out/bin/
    '';
    meta = with pkgs.lib; {
      description = "Only the ts binary from moreutils";
      platforms = platforms.darwin;
    };
  };

in {
  home.username = "coneill";
  home.homeDirectory = "/Users/coneill";
  home.stateVersion = "24.05";

  programs.home-manager.enable = true;

  xdg.configFile."home-manager".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles";

  home.packages = with pkgs; [
    argocd
    atool
    atuin
    bash
    bash-completion
    bun
    dust
    cachix
    codeowners
    codex
    curl
    direnv
    fd
    ffmpeg
    fzf
    gh
    git
    git-crypt
    kubernetes-helm
    htop
    jq
    k9s
    kubecolor
    kubectx
    kubectl
    lftp
    lsd
    mtr
    nix-search-cli
    nmap
    nodejs_24
    p7zip
    patchutils_0_4_2
    prettyping
    pstree
    pv
    rclone
    restic
    ripgrep
    socat
    timer
    tmux
    todoist
    uv
    vim
    wget
    xz
    yadm
    yq-go
    yt-dlp
  ] ++ lib.optionals pkgs.stdenv.isDarwin [
    watch-only
    coreutils-partial
    ts-only
  ];
}
