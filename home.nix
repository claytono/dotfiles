{ config, pkgs, lib, codexPkg, memexPkg, memexSource, ... }:

let
  username = "coneill";
  homeDirectory = if pkgs.stdenv.isDarwin then "/Users/${username}" else "/home/${username}";

  launchdPath = packages:
    lib.concatStringsSep ":" (
      lib.optionals (packages != [ ]) [ (lib.makeBinPath packages) ]
      ++ [ "/usr/bin" "/bin" "/usr/sbin" "/sbin" ]
    );

  launchdEnvironment = { packages ? [ ], extra ? { } }:
    {
      HOME = homeDirectory;
      SHELL = "${pkgs.bash}/bin/bash";
      PATH = launchdPath packages;
    } // extra;

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

  dagu =
    pkgs.stdenv.mkDerivation rec {
      pname = "dagu";
      version = "2.3.8";
      src = pkgs.fetchurl {
        url = "https://github.com/dagu-org/dagu/releases/download/v${version}/dagu_${version}_darwin_arm64.tar.gz";
        hash = "sha256-FKZ4H2/QhVgFEqKHKWjJ2mBLvubdZrqLul6Gp5sz4bM=";
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

  node-exporter-wrapper = pkgs.writeShellScript "node-exporter-wrapper" ''
    set -u

    while true; do
      tailscale_ip=$(tailscale ip -4 2>/dev/null | sed -n '1p')
      if [ -n "$tailscale_ip" ]; then
        exec ${pkgs.prometheus-node-exporter}/bin/node_exporter \
          --web.listen-address=127.0.0.1:9100 \
          --web.listen-address="$tailscale_ip:9100"
      fi

      echo "node-exporter: waiting for Tailscale IPv4 address" >&2
      sleep 10
    done
  '';

in {
  home.username = username;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "24.05";

  programs.home-manager.enable = true;

  programs.memex = {
    enable = true;
    package = memexPkg;
    settings = {
      embeddings = true;
      model = "gemma";
      execution_provider = "cpu";
      auto_index_on_search = false;
      index_service_mode = "continuous";
      index_service_poll_interval = 300;
    } // lib.optionalAttrs pkgs.stdenv.isDarwin {
      index_service_label = "com.memex.index";
      index_service_plist = "${homeDirectory}/Library/LaunchAgents/com.memex.index.plist";
    };
  };

  programs.git = {
    enable = true;

    signing = {
      key = "clayton@oneill.net";
      signByDefault = pkgs.stdenv.isDarwin;
      format = "openpgp";
    };

    settings = {
      user = {
        name = "Clayton O'Neill";
        email = "clayton@oneill.net";
      };
      alias = {
        lg = "log --oneline --graph --all --decorate --abbrev-commit";
      };
      color = {
        diff = "auto";
        status = "auto";
        branch = "auto";
        ui = "auto";
      };
      core.excludesfile = "~/.gitignore";
      branch.autosetuprebase = "always";
      log = {
        decorate = true;
        mailmap = true;
      };
      github.user = "claytono";
      protocol.version = 2;
      push = {
        default = "current";
        autoSetupRemote = true;
      };
      init.defaultBranch = "main";
      pull.rebase = true;
      "url \"git@github.com:\"".pushInsteadOf = "https://github.com/";
    } // lib.optionalAttrs pkgs.stdenv.isDarwin {
      credential.helper = "osxkeychain";
    };
  };

  xdg.configFile."home-manager".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles";
  xdg.configFile."zellij/config.kdl".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles/.config/zellij/config.kdl";
  xdg.configFile."zellij/layouts/main.kdl".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles/.config/zellij/layouts/main.kdl";

  home.file.".bash_profile".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles/.bash_profile";
  home.file.".bashrc".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles/.bashrc";
  home.file.".agents/skills/memex-search" = {
    source = memexSource + "/skills/memex-search";
    force = true;
  };
  home.file.".claude/skills/memex-search" = {
    source = memexSource + "/skills/memex-search";
    force = true;
  };
  home.file.".memex/config.toml".force = true;
  home.file.".codex/skills/renovate-eval" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/github-actions/renovate-eval";
  };
  home.file.".tmux.conf".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles/.tmux.conf";
  home.file."bin/ssh-known-hosts-update".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles/scripts/ssh-known-hosts-update";
  home.file."bin/cco-claude" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles/scripts/cco-claude";
    force = true;
  };
  home.file."bin/cco-codex" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles/scripts/cco-claude";
    force = true;
  };
  home.file."bin/cco-opencode" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles/scripts/cco-claude";
    force = true;
  };
  home.file."bin/cco-claude-safe" = {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/src/dotfiles/scripts/cco-claude-safe";
    force = true;
  };

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
    codexPkg
    curl
    direnv
    diskus
    fd
    ffmpeg
    fzf
    gh
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
    prometheus-node-exporter
    python3
    pstree
    pv
    rclone
    restic
    ripgrep
    rtk
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
    zellij
  ] ++ lib.optionals pkgs.stdenv.isDarwin [
    watch-only
    coreutils-partial
    ts-only
    dagu
  ];

  launchd.agents.dagu = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${config.home.homeDirectory}/src/dotfiles/config/dagu/dagu-wrapper.sh"
      ];
      EnvironmentVariables = launchdEnvironment {
        packages = [
          dagu
          pkgs.coreutils
        ];
        extra = {
          DAGU_AUTH_MODE = "none";
        };
      };
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/.local/share/dagu/dagu.stdout.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/share/dagu/dagu.stderr.log";
    };
  };

  launchd.agents."node-exporter" = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      ProgramArguments = [
        "${node-exporter-wrapper}"
      ];
      EnvironmentVariables = launchdEnvironment {
        packages = [
          pkgs.coreutils
          pkgs.gnused
          pkgs.tailscale
        ];
      };
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/.local/share/prometheus-exporters/node-exporter.stdout.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/share/prometheus-exporters/node-exporter.stderr.log";
    };
  };

  launchd.agents.memex = lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      Label = "com.memex.index";
      ProgramArguments = [
        "${memexPkg}/bin/memex"
        "index"
        "--watch"
        "--watch-interval"
        "300"
      ];
      EnvironmentVariables = launchdEnvironment { };
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/.memex/index-service.log";
      StandardErrorPath = "${config.home.homeDirectory}/.memex/index-service.err.log";
    };
  };

  home.activation.daguDataDir = lib.mkIf pkgs.stdenv.isDarwin (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${config.home.homeDirectory}/.local/share/dagu"
  '');

  home.activation.prometheusExportersDataDir = lib.mkIf pkgs.stdenv.isDarwin (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${config.home.homeDirectory}/.local/share/prometheus-exporters"
  '');
}
