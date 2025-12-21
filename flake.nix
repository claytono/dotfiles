{
  description = "My personal Nix packages";

  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs";

    # Include the nix-search-cli flake
    nix-search-cli = {
      url = "github:peterldowns/nix-search-cli";
    };

    # Include strace-macos
    strace-macos = {
      url = "github:Mic92/strace-macos";
    };
  };

  outputs = { self, nixpkgs, nix-search-cli, strace-macos }:
    let
      supportedSystems = nixpkgs.lib.systems.flakeExposed;
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          # Reference the nix-search-cli package from its flake
          nix-search = nix-search-cli.packages.${system}.default;

          # Reference the strace-macos package from its flake (macOS only)
          strace = if pkgs.stdenv.isDarwin
            then strace-macos.packages.${system}.default
            else null;

          # Custom package to include only the watch binary from procps on macOS
          watch-only = pkgs.stdenv.mkDerivation {
            name = "watch-only";

            # Skip unnecessary build phases
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

            # Skip unnecessary build phases
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

            # Skip unnecessary build phases
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
          default = pkgs.buildEnv {
            name = "my-packages";
            paths = with pkgs; [
              argocd
              atool
              atuin
              bash
              bash-completion
              dust
              cachix
              codeowners
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
              nix-search
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
              tmux
              todoist
              uv
              vim
              wget
              xz
              yadm
              yq-go
              yt-dlp

              (pkgs.lib.optionalString (pkgs.stdenv.isDarwin) watch-only)
              (pkgs.lib.optionalString (pkgs.stdenv.isDarwin) coreutils-partial)
              (pkgs.lib.optionalString (pkgs.stdenv.isDarwin) ts-only)
              (pkgs.lib.optionalString (pkgs.stdenv.isDarwin) strace)
            ];
          };
        }
      );
    };
}
