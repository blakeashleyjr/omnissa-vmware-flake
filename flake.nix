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
      
      omnissaHorizonClientFiles = pkgs.stdenv.mkDerivation {
        pname = "omnissa-horizon-files";
        version = horizonVersion;
        
        src = pkgs.fetchurl {
          url = "https://download3.omnissa.com/software/CART26FQ1_LIN64_DEBPKG_2503/Omnissa-Horizon-Client-2503-8.15.0-14256322247.x64.deb";
          sha256 = "sha256-D4xE5cXiPODlUrEqag/iHkZjEkpxY/rOABwx4xsKRV0=";
        };
        
        nativeBuildInputs = with pkgs; [ dpkg makeWrapper ];
        
        unpackPhase = ''
          dpkg-deb -x $src .
        '';
        
        installPhase = ''
          mkdir -p $out
          cp -r usr/* $out/
          cp -r etc $out/ || true
          
          # Fix permissions
          chmod -R u+w $out
          
          # Remove bundled libraries that cause issues
          rm -f $out/lib/omnissa/gcc/libstdc++.so.6 || true
          rm -f $out/lib/omnissa/libpng16.so.16 || true
          
          # Fix hardcoded paths in the horizon-client script
          substituteInPlace $out/bin/horizon-client \
            --replace "/usr/lib/omnissa" "$out/lib/omnissa" \
            --replace "/usr/bin" "$out/bin" || true
          
          # Create wrapper that sets GTK theme
          makeWrapper "$out/bin/horizon-client" "$out/bin/horizon-client_wrapper" \
            --set GTK_THEME Adwaita \
            --suffix XDG_DATA_DIRS : "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}"
        '';
      };

      omnissaFHSEnv = pkgs.buildFHSEnv {
        name = "omnissa-horizon-client-fhs";
        version = horizonVersion;
        
        runScript = "${omnissaHorizonClientFiles}/bin/horizon-client_wrapper";
        
        targetPkgs = pkgs: with pkgs; [
          at-spi2-atk
          atk
          cairo
          dbus
          file
          fontconfig
          freetype
          gdk-pixbuf
          glib
          gtk2
          gtk3
          harfbuzz
          liberation_ttf
          libjpeg
          libpng
          libpulseaudio
          libtiff
          libudev0-shim
          libuuid
          libv4l
          libxml2
          pango
          pcsclite
          pixman
          udev
          omnissaHorizonClientFiles
          xorg.libX11
          xorg.libXau
          xorg.libXcursor
          xorg.libXext
          xorg.libXi
          xorg.libXinerama
          xorg.libxkbfile
          xorg.libXrandr
          xorg.libXrender
          xorg.libXScrnSaver
          xorg.libXtst
          zlib
          
          # Additional libraries
          openssl
          nspr
          nss
          alsa-lib
          libcap
          libusb1
          mesa
          libva
          libvdpau
          libdrm
          gst_all_1.gstreamer
          gst_all_1.gst-plugins-base
          opensc
          
          # Create symlinks for compatibility
          (pkgs.runCommand "libxml2-compat" {} ''
            mkdir -p $out/lib
            ln -s ${libxml2.out}/lib/libxml2.so $out/lib/libxml2.so.2
          '')
        ];
      };

      desktopItem = pkgs.makeDesktopItem {
        name = "omnissa-horizon-client";
        desktopName = "Omnissa Horizon Client";
        icon = "${omnissaHorizonClientFiles}/share/icons/horizon-client.png";
        exec = "${omnissaFHSEnv}/bin/omnissa-horizon-client-fhs %u";
        mimeTypes = [ "x-scheme-handler/vmware-view" ];
      };

      horizon-client = pkgs.stdenv.mkDerivation {
        pname = "omnissa-horizon-client";
        version = horizonVersion;
        
        dontUnpack = true;
        
        nativeBuildInputs = [ pkgs.copyDesktopItems ];
        
        desktopItems = [ desktopItem ];
        
        installPhase = ''
          runHook preInstall
          mkdir -p $out/bin
          ln -s ${omnissaFHSEnv}/bin/omnissa-horizon-client-fhs $out/bin/vmware-view
          ln -s ${omnissaFHSEnv}/bin/omnissa-horizon-client-fhs $out/bin/horizon-client
          runHook postInstall
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
        buildInputs = [ horizon-client ];
        shellHook = ''
          echo "Horizon client available as 'vmware-view' or 'horizon-client'"
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