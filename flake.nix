{
  description = "Omnissa Horizon Client flake for Nix-based systems";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    ...
  }: let
    horizonVersion = "2503-8.15.0-14256322247";
  in
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      src = pkgs.fetchurl {
        url = "https://download3.omnissa.com/software/CART26FQ1_LIN64_DEBPKG_2503/Omnissa-Horizon-Client-2503-8.15.0-14256322247.x64.deb";
        sha256 = "sha256-D4xE5cXiPODlUrEqag/iHkZjEkpxY/rOABwx4xsKRV0=";
      };

      horizon-client = pkgs.stdenv.mkDerivation {
        pname = "omnissa-horizon-client";
        version = horizonVersion;

        inherit src;
        # The Debian archive is an 'ar' container → data.tar.(xz|zst|gz) inside
        unpackPhase = ''
          runHook preUnpack
          ar x "$src"
          tar -xf data.tar.*     # creates ./usr, ./etc, ...
          runHook postUnpack
        '';

        nativeBuildInputs = [pkgs.autoPatchelfHook pkgs.patchelf pkgs.binutils pkgs.makeWrapper];
        # Run-time deps discovered by `autoPatchelfHook`
        buildInputs = with pkgs; [
          gtk3 # libgtk-3-0
          libxml2.out
          openssl
          nspr
          nss
          fontconfig
          freetype
          alsa-lib
          libpulseaudio
          libcap
          xorg.libX11
          xorg.libXtst
          xorg.libXext
          xorg.libXi
          xorg.libXrandr
          xorg.libxkbfile
          xorg.libXScrnSaver # for libXss.so.1
          libusb1
          mesa # for libgbm.so.1
          libva # for libva.so.1 and libva.so.2
          libvdpau
          libdrm
          gst_all_1.gstreamer
          gst_all_1.gst-plugins-base # for libgstapp-1.0.so.0 and libgstbase-1.0.so.0
          libv4l # for libv4l2.so.0
          pcsclite # for libpcsclite.so.1
          file # for libmagic.so.1
        ];

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          
          # Copy available directories
          for dir in etc opt usr; do
            if [ -d "$dir" ]; then
              cp -r "$dir" $out/
            fi
          done

          # Desktop entry & icon convenience - only if it exists
          if [ -f usr/share/applications/vmware-view.desktop ]; then
            install -Dm644 usr/share/applications/vmware-view.desktop \
                          $out/share/applications/vmware-view.desktop
          fi
          
          # Also copy horizon-client.desktop if it exists
          if [ -f usr/share/applications/horizon-client.desktop ]; then
            install -Dm644 usr/share/applications/horizon-client.desktop \
                          $out/share/applications/horizon-client.desktop
          fi

          runHook postInstall
        '';

        # AutoPatchelf substitutes all RPATHs automatically
        dontConfigure = true;
        dontBuild = true;

        autoPatchelfIgnoreMissingDeps = [
          "libva.so.1"
          "libva-drm.so.1"
          "libva-x11.so.1"
        ];

        # Fix hardcoded paths in scripts
        preFixup = ''
          # Fix paths in the horizon-client script
          substituteInPlace $out/usr/bin/horizon-client \
            --replace "/usr/lib/omnissa" "$out/usr/lib/omnissa" \
            --replace "/usr/bin" "$out/usr/bin"
        '';
        
        # Create wrapper scripts
        postFixup = ''
          # Create bin directory
          mkdir -p $out/bin
          
          # Create a wrapper script that sets up the environment properly
          cat > $out/bin/vmware-view << EOF
          #!${pkgs.bash}/bin/bash
          export LD_LIBRARY_PATH="${pkgs.libxml2.out}/lib\''${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
          exec "$out/usr/bin/horizon-client" "\$@"
          EOF
          chmod +x $out/bin/vmware-view
          
          # Create horizon-client alias
          ln -s $out/bin/vmware-view $out/bin/horizon-client
          
          # Also patch the desktop file to use our wrapper
          if [ -f $out/share/applications/horizon-client.desktop ]; then
            substituteInPlace $out/share/applications/horizon-client.desktop \
              --replace "Exec=/usr/bin/horizon-client" "Exec=$out/bin/horizon-client"
          fi
        '';

        meta = with pkgs.lib; {
          description = "Omnissa (VMware) Horizon Client for Linux";
          homepage = "https://www.omnissa.com/";
          license = licenses.unfree;
          platforms = platforms.linux;
          maintainers = with maintainers; [];
        };
      };
    in {
      packages.horizon-client = horizon-client;
      packages.default = horizon-client;

      devShells.default = pkgs.mkShell {
        nativeBuildInputs = [pkgs.autoPatchelfHook pkgs.patchelf];
        buildInputs = horizon-client.buildInputs;
        shellHook = ''
          echo "Horizon dev shell – binaries available under $HORIZON_ROOT"
          export HORIZON_ROOT=${horizon-client}
        '';
      };
    })
    // {
      # flake-level exports that don't vary per system
      nixosModules.horizon-client = {
        lib,
        config,
        pkgs,
        ...
      }: let
        cfg = config.services.horizon-client;
      in {
        options.services.horizon-client = {
          enable = lib.mkEnableOption "Omnissa Horizon Client";
          package = lib.mkOption {
            type = lib.types.package;
            default = self.packages.${pkgs.system}.horizon-client;
            description = "Which package to install.";
          };
          extraEnv = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            description = "Extra environment variables passed globally.";
          };
        };

        config = lib.mkIf cfg.enable {
          assertions = [
            {
              assertion = config.nixpkgs.config.allowUnfree or false;
              message = "services.horizon-client requires `nixpkgs.config.allowUnfree = true;`";
            }
          ];

          environment.systemPackages = [cfg.package];

          services.udev.packages = [cfg.package];
          # Global env tweaks (GTK theme hints, etc.)
          environment.variables = cfg.extraEnv;
        };
      };

      nixosModules.default = self.nixosModules.horizon-client;

      overlays.horizon-client = final: prev: {
        omnissa-horizon-client = self.packages.${prev.system}.horizon-client;
      };

      overlays.default = self.overlays.horizon-client;
    };
}