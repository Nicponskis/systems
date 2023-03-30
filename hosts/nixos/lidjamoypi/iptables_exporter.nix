# TODO(Dave): Migrate this to a shared spot somewhere
{
  config, lib, pkgs, utils

  , ...
} @ inputs:

let
  cfg = config.services.iptables_exporter;
in {
  options.services.iptables_exporter = {
    enable = lib.mkEnableOption {
      name = "iptables_exporter";
    };

    port = lib.mkOption {
      default = 9100;
      description = "Port to listen on";
      type = lib.types.port;
    };

    ipv4 = lib.mkOption {
      default = true;
      description = "Export ipv4 iptables";
      type = lib.types.bool;
    };

    ipv6 = lib.mkOption {
      default = true;
      description = "Export ipv6 ip6tables";
      type = lib.types.bool;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.ipv4 || cfg.ipv6;
      message = "At least one of `ipv4` or `ipv6` must be enabled.";
    }];

    nixpkgs.overlays = [
      (final: prev: {
        # TODO(dave): fix the build.
        iptables_exporter = /*final.rustPlatform.buildRustPackage rec {
          pname = "iptables_exporter";
          version = "0.3.0";
          src = final.fetchFromGitHub {
            owner = "kbknapp";
            repo = pname;
            rev = "refs/tags/v${version}";  # Ref is ambiguous, branch w/ same name exists :(
            hash = "sha256-XV2XuCfmgU5aJQNYrqYmcJwYnQ0OojEaDgCHT3fVmiw=";
          };
          cargoHash = "sha256-h3luLICTCVuZZCmNjeOzftWUjZvtcxXeyYGErwG/QHo=";
          meta = with final.lib; {
            platforms = ["aarch64-linux"];
          };
        }; */
        final.fetchzip {
          url = "https://github.com/virusdave/iptables_exporter/releases/download/v0.3.3/iptables_exporter-v0.3.3-aarch64-linux-musl.tar.gz";
          name = "iptables-exporter";
          version = "0.3.3";
          stripRoot = false;
          hash = "sha256-QLyEcvmbmtUzC+I2qRvCnkNJg+0UfseZOJFMWPSmlhs=";
          postFetch = ''
            mkdir $out/bin
            mv $out/iptables_exporter $out/bin
            '';
          meta.platforms = ["aarch64-linux"];
        };
      })
    ];

    systemd.services."prometheus-iptables_exporter" = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = [ pkgs.iptables ];
      serviceConfig = let
        caps = [
          "CAP_DAC_READ_SEARCH"
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ] ++ lib.optionals (cfg.port < 1024) [ "CAP_NET_BIND_SERVICE" ];
      in {
        ExecStart = "${pkgs.iptables_exporter}/bin/iptables_exporter" +
          lib.optionalString cfg.ipv4 " -t iptables" +
          lib.optionalString cfg.ipv6 " -t ip6tables" +
          " -p ${toString cfg.port}";
        User = "iptables_exporter";
        # User = "root";  # TODO(dave): This is lame, and shouldn't be necessary.
        Restart = "always";
        WorkingDirectory = "/var/lib/iptables_exporter";
        # Required capabilities
        AmbientCapabilities = caps;
        CapabilityBoundingSet = caps;
        # Hardening
        DeviceAllow = [ "/dev/null rw" ];
        DevicePolicy = "strict";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        # PrivateUsers = true;  # This looks like the culprit.
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "full";
        RemoveIPC = true;
        RestrictAddressFamilies = [ "AF_NETLINK" "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/iptables_exporter 0700 iptables_exporter iptables_exporter"
    ];

    users.groups.iptables_exporter = {};

    users.users.iptables_exporter = {
      description = "iptables_exporter system daemon user";
      group = "iptables_exporter";
      isSystemUser = true;
    };
  };
}
