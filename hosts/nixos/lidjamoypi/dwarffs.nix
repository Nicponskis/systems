# TODO(Dave): Migrate this to a shared spot somewhere
{
  config, lib, pkgs, utils

  , ...
} @ inputs:

let
  cfg = config.services.dwarffs;
in {
  options.services.dwarffs = {
    enable = lib.mkEnableOption {
      name = "dwarffs";
    };

    cache = lib.mkOption {
      default = "/var/cache/dwarffs";
      description = "Location to use as a debug artifact cache";
      type = lib.types.str;
    };

    gc = lib.mkOption {
      default = true;
      description = "Whether to automatically garbage collect cached debuginfo older than gcDelay";
      type = lib.types.bool;
    };

    gcDelay = lib.mkOption {
      default = "7d";
      description = "If cache garbage collection is enabled, remove cached items older than this age";
      type = lib.types.str;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.variables.NIX_DEBUG_INFO_DIRS = [ "/run/dwarffs" ];

    fileSystems."/run/dwarffs" = {
      device = "${pkgs.dwarffs}/bin/dwarffs";
      fsType = "fuse";
      noCheck = true;
      options = [
        "ro" "allow_other"
        "cache=${cfg.cache}"
        "uid=dwarffs" "gid=dwarffs"
      ];
    };

    nixpkgs.overlays = [
      (final: prev: {
        dwarffs = let
          rev = "1f850df9c932acb95da2f31b576a8f6c7c188376";
          hash = "sha256-HBgQB8jzmpBTHAdPfCtLnxVhHSzI3XtSfcMW2TZ0KN8=";
          in with final; let nix = final.nix; in pkgs.stdenv.mkDerivation rec {
            pname = "dwarffs";
            version = "0.1.${lib.substring 0 8 rev}";

            buildInputs = [ fuse nix nlohmann_json boost ];
            NIX_CFLAGS_COMPILE = "-I ${nix.dev}/include/nix -include ${nix.dev}/include/nix/config.h -D_FILE_OFFSET_BITS=64 -DVERSION=\"${version}\"";

            src = fetchFromGitHub {
              owner = "edolstra";
              repo = "dwarffs";
              name = "dwarffs-source";
              inherit rev hash;
            };

            installPhase = ''
              mkdir -p $out/bin
              cp dwarffs $out/bin
            '';
          };
      })
    ];

    system.fsPackages = [ pkgs.dwarffs ];

    systemd.tmpfiles.rules = let delay = if cfg.gc then cfg.gcDelay else ""; in [
      # dwarffs debug info cache.  Setting cleanup to quite fast!  Let's see
      # if it works once a network fs is mounted over top of it...
      "d ${cfg.cache} 0755 dwarffs dwarffs ${delay}"
    ];

    users.groups.dwarffs = {};

    users.users.dwarffs = {
      description = "Debug symbols file system daemon user";
      group = "dwarffs";
      isSystemUser = true;
    };
  };
}
