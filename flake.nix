{
  description = "My personal Nix packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    codex.url = "github:openai/codex?ref=rust-v0.147.0";

    memex = {
      url = "github:nicosuave/memex?ref=v0.11.6";
      flake = false;
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Include the nix-search-cli flake
    nix-search-cli = {
      url = "github:peterldowns/nix-search-cli";
    };

    # Include strace-macos
    strace-macos = {
      url = "github:Mic92/strace-macos";
    };
  };

  outputs = { self, nixpkgs, codex, memex, home-manager, nix-search-cli, strace-macos }:
    let
      pkgsFor = system: nixpkgs.legacyPackages.${system};
      codexSource = codex.outPath;
      codexVersion =
        (builtins.fromTOML (builtins.readFile (codexSource + "/codex-rs/Cargo.toml")))
        .workspace.package.version;
      codexReleasePackages = {
        aarch64-darwin = {
          target = "aarch64-apple-darwin";
          hash = "sha256-F7KYTrIrYH49DCVyglL8kPUQ5Ha605ptn0XNsapoVDI=";
        };
        aarch64-linux = {
          target = "aarch64-unknown-linux-musl";
          hash = "sha256-icv3m9Wub5xY2kfoB58xHIQhk1DJxDwHDULz6bKoFAE=";
        };
        x86_64-linux = {
          target = "x86_64-unknown-linux-musl";
          hash = "sha256-vXWNU9VuQdxl4EX0WJ33mgOO0ZegEa3LUqJY5q1kz9o=";
        };
      };
      memexSource = memex;
      memexVersion =
        (builtins.fromTOML (builtins.readFile (memexSource + "/Cargo.toml")))
        .package.version;
      memexReleasePackages = {
        aarch64-darwin = {
          asset = "macos-arm64";
          hash = "sha256-II3dIHNjVlGvL+kAdAAC9628bS8IXlwMSV3/GeTIU5U=";
        };
      };
      supportedSystems = builtins.attrNames codexReleasePackages;
      memexSystems = builtins.attrNames memexReleasePackages;
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      codexFixedOutputs = map (system:
        let release = codexReleasePackages.${system};
        in {
          input = "codex";
          file = "flake.nix";
          attrPath = [ "codexReleasePackages" system "hash" ];
          url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-package-${release.target}.tar.gz";
          hashType = "sha256";
        }) supportedSystems;
      memexFixedOutputs = map (system:
        let release = memexReleasePackages.${system};
        in {
          input = "memex";
          file = "flake.nix";
          attrPath = [ "memexReleasePackages" system "hash" ];
          url = "https://github.com/nicosuave/memex/releases/download/v${memexVersion}/memex-${memexVersion}-${release.asset}.tar.gz";
          hashType = "sha256";
        }) memexSystems;
      refreshableFixedOutputs = codexFixedOutputs ++ memexFixedOutputs;
      codexPackage = {
        fetchurl,
        lib,
        installShellFiles,
        stdenvNoCC,
        versionCheckHook,
        installShellCompletions ? stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform,
        ...
      }:
        let release = codexReleasePackages.${stdenvNoCC.hostPlatform.system};
        in stdenvNoCC.mkDerivation (finalAttrs: {
          pname = "codex";
          version = codexVersion;

          src = fetchurl {
            url = "https://github.com/openai/codex/releases/download/rust-v${finalAttrs.version}/codex-package-${release.target}.tar.gz";
            hash = release.hash;
          };
          sourceRoot = ".";

          nativeBuildInputs = [
            installShellFiles
          ];

          dontConfigure = true;
          dontBuild = true;

          installPhase = ''
            runHook preInstall

            mkdir -p $out
            cp -R . $out/

            runHook postInstall
          '';

          postInstall = lib.optionalString installShellCompletions ''
            installShellCompletion --cmd codex \
              --bash <($out/bin/codex completion bash) \
              --fish <($out/bin/codex completion fish) \
              --zsh <($out/bin/codex completion zsh)
          '';

          doInstallCheck = true;
          nativeInstallCheckInputs = [ versionCheckHook ];

          meta = {
            description = "Lightweight coding agent that runs in your terminal";
            homepage = "https://github.com/openai/codex";
            changelog = "https://raw.githubusercontent.com/openai/codex/refs/tags/rust-v${finalAttrs.version}/CHANGELOG.md";
            license = lib.licenses.asl20;
            mainProgram = "codex";
            platforms = lib.platforms.unix;
          };
        });
      codexPkgFor = system: (pkgsFor system).callPackage codexPackage {
      };
      memexPackage = {
        fetchurl,
        lib,
        stdenvNoCC,
        versionCheckHook,
        ...
      }:
        let release = memexReleasePackages.${stdenvNoCC.hostPlatform.system};
        in stdenvNoCC.mkDerivation (finalAttrs: {
          pname = "memex";
          version = memexVersion;

          src = fetchurl {
            url = "https://github.com/nicosuave/memex/releases/download/v${finalAttrs.version}/memex-${finalAttrs.version}-${release.asset}.tar.gz";
            hash = release.hash;
          };
          sourceRoot = ".";

          dontConfigure = true;
          dontBuild = true;

          installPhase = ''
            runHook preInstall

            install -Dm755 memex $out/bin/memex

            runHook postInstall
          '';

          doInstallCheck = true;
          nativeInstallCheckInputs = [ versionCheckHook ];

          meta = {
            description = "Fast local history search for local agent logs";
            homepage = "https://github.com/nicosuave/memex";
            license = lib.licenses.mit;
            mainProgram = "memex";
            platforms = memexSystems;
          };
        });
      memexPkgFor = system: (pkgsFor system).callPackage memexPackage {
      };
      homeConfigurationFor = system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor system;
          modules = [
            (memexSource + "/nix/hm-module.nix")
            ./home.nix
          ];
          extraSpecialArgs = {
            inherit memexSource nix-search-cli strace-macos;
            codexPkg = codexPkgFor system;
            memexPkg = if builtins.hasAttr system memexReleasePackages then memexPkgFor system else null;
          };
        };
      systemHomeConfigurations =
        builtins.listToAttrs (map (system: {
          name = "coneill-${system}";
          value = homeConfigurationFor system;
        }) supportedSystems);
    in {
      lib = {
        inherit codexReleasePackages memexReleasePackages memexSource refreshableFixedOutputs supportedSystems;
      };

      packages = forAllSystems (system:
        {
          codex = codexPkgFor system;
          default = codexPkgFor system;
        }
        // nixpkgs.lib.optionalAttrs (builtins.hasAttr system memexReleasePackages) {
          memex = memexPkgFor system;
        });

      homeConfigurations = systemHomeConfigurations // {
        coneill = systemHomeConfigurations.coneill-aarch64-darwin;
      };

      devShells = forAllSystems (system:
        let pkgs = pkgsFor system;
        in {
          default = pkgs.mkShell {
            packages = [
              pkgs.pre-commit
              pkgs.shellcheck
              (pkgs.python313.withPackages (ps: [ ps.pyyaml ]))
            ];
          };
        }
      );
    };
}
