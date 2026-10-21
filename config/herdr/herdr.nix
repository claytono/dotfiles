# herdr: the package, its plugins, and on macOS the Herdr.app bundle that
# starts its servers. Imported from home.nix.
{ config, pkgs, lib, ... }:

let
  # On macOS, `herdr` starts missing servers through Herdr.app so their panes
  # keep Local Network access; see herdr-wrapper.sh. The real binary's
  # completions and other files are kept.
  herdrWrapper = pkgs.writeShellScriptBin "herdr" (
    builtins.replaceStrings [ "@herdr@" "@jq@" ] [ "${pkgs.herdr}/bin/herdr" "${pkgs.jq}/bin/jq" ]
      (builtins.readFile ./herdr-wrapper.sh)
  );
  herdrWithApp = pkgs.symlinkJoin {
    name = "herdr-${pkgs.herdr.version}";
    paths = [ herdrWrapper pkgs.herdr ];
  };
in {
  home.packages = [
    (if pkgs.stdenv.hostPlatform.isDarwin then herdrWithApp else pkgs.herdr)
  ];

  # herdr records linked plugins in its own ~/.config/herdr/plugins.json, so
  # register them here. Linking an already-linked path is a no-op.
  home.activation.herdrPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.herdr}/bin/herdr plugin link \
      "${config.home.homeDirectory}/src/dotfiles/config/herdr/plugins/direnv-worktree-allow" >/dev/null
  '';

  # Build Herdr.app and install it only when its code signature changes, so
  # an unchanged rebuild leaves the installed bundle alone. Privacy grants
  # survived a signature change in testing, apparently following the bundle
  # ID, so a change only prints a note in case one is lost.
  home.activation.herdrApp = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # A subshell, so its trap removes the build directory however it exits.
    (
      herdr_app="${config.home.homeDirectory}/Library/Application Support/net.oneill.herdr/Herdr.app"
      herdr_build=$(mktemp -d)
      trap 'rm -rf "$herdr_build"' EXIT
      mkdir -p "$herdr_build/Herdr.app/Contents/MacOS"
      ${pkgs.stdenv.cc}/bin/cc -O2 -o "$herdr_build/Herdr.app/Contents/MacOS/Herdr" ${./app/launcher.c}
      install -m 0644 ${./app/Info.plist} "$herdr_build/Herdr.app/Contents/Info.plist"
      printf 'APPL????' > "$herdr_build/Herdr.app/Contents/PkgInfo"
      if ! herdr_sign=$(/usr/bin/codesign --force --sign - "$herdr_build/Herdr.app" 2>&1); then
        errorEcho "Signing Herdr.app failed: $herdr_sign"
        exit 1
      fi

      herdr_cdhash() {
        /usr/bin/codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p'
      }
      herdr_new=$(herdr_cdhash "$herdr_build/Herdr.app")
      herdr_old=""
      if [ -d "$herdr_app" ]; then
        # A damaged or unsigned bundle has no hash; replace it rather than
        # fail every switch.
        herdr_old=$(herdr_cdhash "$herdr_app" || true)
      fi

      if [ "$herdr_new" != "$herdr_old" ]; then
        run mkdir -p "$(dirname "$herdr_app")"
        run rm -rf "$herdr_app"
        run mv "$herdr_build/Herdr.app" "$herdr_app"
        noteEcho "Herdr.app changed. If programs in herdr panes lose access to the local network, microphone or another privacy permission, re-enable Herdr under System Settings > Privacy & Security."
      fi
    )
  '');
}
