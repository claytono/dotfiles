{
  description = "My personal Nix packages";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    codex.url = "github:openai/codex?ref=rust-v0.124.0";

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
      supportedSystems = [ "aarch64-darwin" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      darwinPkgs = nixpkgs.legacyPackages.aarch64-darwin;
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
      librustyV8 = darwinPkgs.fetchurl {
        url = "https://github.com/denoland/rusty_v8/releases/download/v${codexV8Version}/librusty_v8_release_aarch64-apple-darwin.a.gz";
        hash = "sha256-v+LJvjKlbChUbw+WWCXuaPv2BkBfMQzE4XtEilaM+Yo=";
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
        installShellCompletions ? stdenv.buildPlatform.canExecute stdenv.hostPlatform,
        ...
      }:
        rustPlatform.buildRustPackage (finalAttrs: {
          pname = "codex";
          version = codexVersion;

          src = codexSource;
          sourceRoot = "source/codex-rs";

          cargoHash = "sha256-tuUY+Mg7DwYnYLt1zfqo0rrz5ip0fukxj947yBJAyks=";

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
      codexPkg = darwinPkgs.callPackage codexPackage { };
    in {
      homeConfigurations."coneill" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        modules = [ ./home.nix ];
        extraSpecialArgs = {
          inherit nix-search-cli strace-macos codexPkg;
        };
      };

      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.mkShell {
            packages = [
              pkgs.pre-commit
              (pkgs.python313.withPackages (ps: [ ps.pyyaml ]))
            ];
          };
        });
    };
}
