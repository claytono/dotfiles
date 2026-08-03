{
  description = "My personal Nix packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    codex.url = "github:openai/codex?ref=rust-v0.146.0";

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

  outputs = { self, nixpkgs, codex, home-manager, nix-search-cli, strace-macos }:
    let
      pkgsFor = system: nixpkgs.legacyPackages.${system};
      codexSource = codex.outPath;
      codexVersion =
        (builtins.fromTOML (builtins.readFile (codexSource + "/codex-rs/Cargo.toml")))
        .workspace.package.version;
      codexReleasePackages = {
        aarch64-darwin = {
          target = "aarch64-apple-darwin";
          hash = "sha256-7Ok3Fp1MnpENYIJqbqSueEihbAiUA9Ei5w59pKxBujQ=";
        };
        aarch64-linux = {
          target = "aarch64-unknown-linux-musl";
          hash = "sha256-VPeaBaum+av475iKvK6L8vzvuiC+tUm0/ys6zbLLb1Q=";
        };
        x86_64-linux = {
          target = "x86_64-unknown-linux-musl";
          hash = "sha256-caKNNiyWrJgpv4IDoscb5FGutyatuEMWf9rw6uj+fdk=";
        };
      };
      supportedSystems = builtins.attrNames codexReleasePackages;
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      refreshableFixedOutputs = map (system:
        let release = codexReleasePackages.${system};
        in {
          input = "codex";
          file = "flake.nix";
          attrPath = [ "codexReleasePackages" system "hash" ];
          url = "https://github.com/openai/codex/releases/download/rust-v${codexVersion}/codex-package-${release.target}.tar.gz";
          hashType = "sha256";
        }) supportedSystems;
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
      homeConfigurationFor = system:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor system;
          modules = [ ./home.nix ];
          extraSpecialArgs = {
            inherit nix-search-cli strace-macos;
            codexPkg = codexPkgFor system;
          };
        };
      systemHomeConfigurations =
        builtins.listToAttrs (map (system: {
          name = "coneill-${system}";
          value = homeConfigurationFor system;
        }) supportedSystems);
    in {
      lib = {
        inherit codexReleasePackages refreshableFixedOutputs supportedSystems;
      };

      packages = forAllSystems (system: {
        codex = codexPkgFor system;
        default = codexPkgFor system;
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
