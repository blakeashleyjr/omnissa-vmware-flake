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
        '';
      };

      # Create a wrapper script that sets up the library environment
      wrapperScript = pkgs.writeScript "horizon-client-wrapper" ''
        #!${pkgs.bash}/bin/bash
        # Create a temporary directory for our symlinks
        export TMPDIR=''${TMPDIR:-/tmp}
        LIBDIR=$(mktemp -d "$TMPDIR/horizon-libs-XXXXXX")
        trap "rm -rf $LIBDIR" EXIT
        
        # Create symlink for libxml2.so.2
        ln -s ${pkgs.libxml2.out}/lib/libxml2.so "$LIBDIR/libxml2.so.2"
        
        # Set up library path
        export LD_LIBRARY_PATH="$LIBDIR:${pkgs.lib.makeLibraryPath [
          pkgs.libxml2
          pkgs.glib
          pkgs.gtk3
          pkgs.atk
          pkgs.cairo
          pkgs.pango
          pkgs.fontconfig
          pkgs.freetype
          pkgs.libpulseaudio
          pkgs.alsa-lib
          pkgs.libva
          pkgs.libvdpau
          pkgs.libdrm
          pkgs.mesa
          pkgs.openssl
          pkgs.nspr
          pkgs.nss
          pkgs.libcap
          pkgs.xorg.libX11
          pkgs.xorg.libXext
          pkgs.xorg.libXi
          pkgs.xorg.libXrandr
          pkgs.xorg.libXScrnSaver
          pkgs.xorg.libXtst
          pkgs.xorg.libxkbfile
        ]}:$LD_LIBRARY_PATH"
        
        # Set GTK theme
        export GTK_THEME=Adwaita
        export XDG_DATA_DIRS="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:$XDG_DATA_DIRS"
        
        # Run the actual client
        exec "${omnissaHorizonClientFiles}/bin/horizon-client" "$@"
      '';

      desktopItem = pkgs.makeDesktopItem {
        name = "omnissa-horizon-client";
        desktopName = "Omnissa Horizon Client";
        icon = "${omnissaHorizonClientFiles}/share/icons/horizon-client.png";
        exec = "${wrapperScript} %u";
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
          ln -s ${wrapperScript} $out/bin/vmware-view
          ln -s ${wrapperScript} $out/bin/horizon-client
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