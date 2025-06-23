{
  description = "Omnissa Horizon Client flake for Nix-based systems";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      src = pkgs.fetchurl {
        url = "hhttps://download3.omnissa.com/software/CART26FQ1_LIN64_DEBPKG_2503/Omnissa-Horizon-Client-2503-8.15.0-14256322247.x64.deb";
        sha256 = "sha256-D4xE5cXiPODlUrEqag/iHkZjEkpxY/rOABwx4xsKRV0=";
      };

      horizon-client = pkgs.stdenv.mkDerivation {
        pname   = "omnissa-horizon-client";

        inherit src;
        sourceRoot = ".";
        # The Debian archive is an 'ar' container → data.tar.(xz|zst|gz) inside
        unpackPhase = ''
          ar x "$src"
          tar -xf data.tar.*     # creates ./usr, ./etc, ...
        '';

        nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.patchelf pkgs.binutils ];
        # Run-time deps discovered by `autoPatchelfHook`
        buildInputs = with pkgs; [
          gtk3_gtk3   # libgtk-3-0
          libxml2
          openssl
          nspr nss
          fontconfig
          freetype
          alsa-lib
          libpulseaudio
          libcap
          xorg.libX11 xorg.libXtst xorg.libXext xorg.libXi xorg.libXrandr
          libusb1
        ];

        installPhase = ''
          mkdir -p $out
          cp -r etc opt usr $out/
          # Desktop entry & icon convenience
          install -Dm644 usr/share/applications/vmware-view.desktop \
                        $out/share/applications/vmware-view.desktop
        '';

        # AutoPatchelf substitutes all RPATHs automatically
        dontConfigure = true;
        dontBuild     = true;

        meta = with pkgs.lib; {
          description = "Omnissa (VMware) Horizon Client for Linux";
          homepage    = "https://www.omnissa.com/";
          license     = licenses.unfree;
          platforms   = platforms.linux;
          maintainers = with maintainers; [ ];
        };
      };

    in {
      packages.horizon-client = horizon-client;
      packages.default        = horizon-client;

      overlays.horizon-client = final: prev: {
        omnissa-horizon-client = horizon-client;
      };

      devShells.default = pkgs.mkShell {
        nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.patchelf ];
        buildInputs = horizon-client.buildInputs;
        shellHook = ''
          echo "Horizon dev shell – binaries available under $HORIZON_ROOT"
          export HORIZON_ROOT=${horizon-client}
        '';
      };

      nixosModules.horizon-client = { lib, config, pkgs, ... }:
      let
        cfg = config.services.horizon-client;
      in {
        options.services.horizon-client = {
          enable = lib.mkEnableOption "Omnissa Horizon Client";
          package = lib.mkOption {
            type        = lib.types.package;
            default     = horizon-client;
            description = "Which package to install.";
          };
          extraEnv = lib.mkOption {
            type        = lib.types.attrsOf lib.types.str;
            default     = {};
            description = "Extra environment variables passed globally.";
          };
        };

        config = lib.mkIf cfg.enable {
          assertions = [{
            assertion  = config.nixpkgs.config.allowUnfree or false;
            message    = "services.horizon-client requires `nixpkgs.config.allowUnfree = true;`";
          }];

          environment.systemPackages = [ cfg.package ];

          services.udev.packages = [ cfg.package ];
          # Global env tweaks (GTK theme hints, etc.)
          environment.variables = cfg.extraEnv;
        };
      };
    })
    // {
      # flake-level exports that don’t vary per system
      nixosModules.default = self.nixosModules.horizon-client;
      overlays.default     = self.overlays.horizon-client;
    };
}
