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

  dagu = pkgs.stdenv.mkDerivation rec {
    pname = "dagu";
    version = "2.3.8";
    src = pkgs.fetchurl {
      url = "https://github.com/dagu-org/dagu/releases/download/v${version}/dagu_${version}_darwin_arm64.tar.gz";
      sha256 = "1cz16fdsg1jypa5vlrnxwsz4nq6sr5l2k1x2282mi1fhdwgpi9hl";
    };
    sourceRoot = ".";
    installPhase = ''
      mkdir -p $out/bin
      cp dagu $out/bin/
      chmod +x $out/bin/dagu
    '';
    meta = with pkgs.lib; {
      description = "A powerful, lightweight workflow engine for scheduling and running complex pipelines";
      homepage = "https://github.com/dagu-org/dagu";
      platforms = [ "aarch64-darwin" ];
    };
  };

in {
  home.username = "coneill";
  home.homeDirectory = "/Users/coneill";
  home.stateVersion = "24.05";

  programs.home-manager.enable = true;

  xdg.configFile."home-manager".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles";

  home.file.".bash_profile".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles/.bash_profile";
  home.file.".bashrc".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles/.bashrc";

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
    pre-commit
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
    dagu
  ];

  launchd.agents.dagu = {
    enable = true;
    config = {
      ProgramArguments = [
        "${config.home.homeDirectory}/src/dotfiles/config/dagu/dagu-wrapper.sh"
      ];
      EnvironmentVariables = {
        HOME = config.home.homeDirectory;
        SHELL = "${pkgs.bash}/bin/bash";
        PATH = "/nix/var/nix/profiles/default/bin:${config.home.homeDirectory}/.nix-profile/bin:${config.home.homeDirectory}/.orbstack/bin:/usr/bin:/bin:/usr/sbin";
        DAGU_AUTH_MODE = "none";
      };
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/.local/share/dagu/dagu.stdout.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/share/dagu/dagu.stderr.log";
    };
  };

  home.activation.daguDataDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${config.home.homeDirectory}/.local/share/dagu"
  '';
}
