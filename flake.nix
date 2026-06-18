{
  description = "My personal Nix packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    codex.url = "github:openai/codex?ref=rust-v0.137.0";

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
      codexCargoLock =
        builtins.fromTOML (builtins.readFile (codexSource + "/codex-rs/Cargo.lock"));
      codexV8Version =
        (nixpkgs.lib.findFirst
          (pkg: pkg.name == "v8")
          (throw "Unable to find v8 crate in Codex Cargo.lock")
          codexCargoLock.package
        ).version;
      rustyV8Archives = {
        aarch64-darwin = {
          platform = "aarch64-apple-darwin";
          hash = "sha256-fnR0DD7woOj8DiaKJYYSPpg0D+lDVmjNwSiPrvtzYq4=";
        };
        aarch64-linux = {
          platform = "aarch64-unknown-linux-gnu";
          hash = "sha256-lMPw/eAFFAT8obaR8opJbXjbgw58+0maBEyxpeOllFU=";
        };
        x86_64-linux = {
          platform = "x86_64-unknown-linux-gnu";
          hash = "sha256-Cd3vbFEZKv/wVBExoO+cAPgxhdI5HaqxgDgqOr82rJU=";
        };
      };
      supportedSystems = builtins.attrNames rustyV8Archives;
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      refreshableFixedOutputs = map (system:
        let archive = rustyV8Archives.${system};
        in {
          input = "codex";
          file = "flake.nix";
          attrPath = [ "rustyV8Archives" system "hash" ];
          url = "https://github.com/denoland/rusty_v8/releases/download/v${codexV8Version}/librusty_v8_release_${archive.platform}.a.gz";
          hashType = "sha256";
        }) supportedSystems;
      librustyV8For = system:
        let
          pkgs = pkgsFor system;
          archive = rustyV8Archives.${system};
        in
          pkgs.fetchurl {
            url = "https://github.com/denoland/rusty_v8/releases/download/v${codexV8Version}/librusty_v8_release_${archive.platform}.a.gz";
            hash = archive.hash;
          };
      codexPackage = {
        lib,
        rustPlatform,
        stdenv,
        installShellFiles,
        bubblewrap,
        clang,
        cmake,
        gitMinimal,
        libcap,
        libclang,
        livekit-libwebrtc,
        makeBinaryWrapper,
        pkg-config,
        openssl,
        ripgrep,
        versionCheckHook,
        librustyV8,
        installShellCompletions ? stdenv.buildPlatform.canExecute stdenv.hostPlatform,
        ...
      }:
        rustPlatform.buildRustPackage (finalAttrs: {
          pname = "codex";
          version = codexVersion;

          src = codexSource;
          sourceRoot = "source/codex-rs";

          cargoHash = "sha256-SX5LMO+IWismbH61Jd0g1mgykfav8DrqG+wjyNCWyCo=";

          cargoBuildFlags = [
            "--package"
            "codex-cli"
          ];
          cargoCheckFlags = [
            "--package"
            "codex-cli"
          ];

          postPatch = ''
            substituteInPlace $cargoDepsCopy/*/webrtc-sys-*/build.rs \
              --replace-fail "cargo:rustc-link-lib=static=webrtc" "cargo:rustc-link-lib=dylib=webrtc"

            substituteInPlace Cargo.toml \
              --replace-fail 'lto = "fat"' "" \
              --replace-fail 'codegen-units = 1' ""
          '';

          nativeBuildInputs = [
            clang
            cmake
            gitMinimal
            installShellFiles
            makeBinaryWrapper
            pkg-config
          ];

          buildInputs = [
            libclang
            openssl
          ]
          ++ lib.optionals stdenv.hostPlatform.isLinux [
            libcap
          ];

          env = {
            LIBCLANG_PATH = "${lib.getLib libclang}/lib";
            LK_CUSTOM_WEBRTC = lib.getDev livekit-libwebrtc;
            NIX_CFLAGS_COMPILE = toString (
              lib.optionals stdenv.cc.isGNU [
                "-Wno-error=stringop-overflow"
              ]
              ++ lib.optionals stdenv.cc.isClang [
                "-Wno-error=character-conversion"
              ]
            );
            RUSTY_V8_ARCHIVE = librustyV8;
          };

          doCheck = false;

          postInstall = lib.optionalString installShellCompletions ''
            installShellCompletion --cmd codex \
              --bash <($out/bin/codex completion bash) \
              --fish <($out/bin/codex completion fish) \
              --zsh <($out/bin/codex completion zsh)
          '';

          postFixup = ''
            wrapProgram $out/bin/codex --prefix PATH : ${
              lib.makeBinPath ([ ripgrep ] ++ lib.optionals stdenv.hostPlatform.isLinux [ bubblewrap ])
            }
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
        librustyV8 = librustyV8For system;
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
        inherit codexV8Version refreshableFixedOutputs rustyV8Archives supportedSystems;
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
