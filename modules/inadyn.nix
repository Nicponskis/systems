{ modulesPath, lib, pkgs, config, ... }:

# Inlined version of an "inadyn" module for DynDNS
# Borrowed wholesale from here:
#   https://github.com/ahbk/my-nixos/blob/master/inadyn/default.nix
let
  inherit (lib) mkOption types mkIf mdDoc;
  cfg = config.services.networking.inadyn;
in {
  options = {

    services.networking.inadyn = with types; {

      enable = lib.mkEnableOption (mdDoc ''
        Synchronize your machine's IP address with a dynamic DNS provider using inadyn
      '');

      logLevel = mkOption {
        type = nullOr (enum ["none" "err" "info" "notice" "debug"]);
        default = null;
        example = "debug";
        description = mdDoc ''
          If set, the value of the `--loglevel=LEVEL` flag to use.
        '';
      };

      configFileContents = mkOption {
        type = nullOr str;
        default = null;
        # example = ./inadyn/extraConfig.conf;
        description = mdDoc ''
          Include this file in `inadyn.conf`.
        '';
      };

      providers = mkOption {
        default = {};
        type = attrsOf (submodule (
          { name, config, options, ... }:
          {
            options = {

              username = mkOption {
                type = str;
                example = "alice@mail.com";
                description = mdDoc ''
                  Username for the provider.
                '';
              };

              passwordFile = mkOption {
                type = path;
                example = "/run/freedns.pw";
                description = mdDoc ''
                  A file containing the password declaration.

                  Note that the full password declaration is needed:
                  ```
                  password=your-secret-password
                  ```
                '';
              };

              provider = mkOption {
                type = str;
                default = name;
                defaultText = "<name>";
                description = mdDoc ''
                  Specify one of the predefined providers, <name> by default.
                  '';
              };

              hostname = mkOption {
                type = str;
                description = mdDoc ''
                  Domain(s) that should point to your IP.
                  '';
                example = "{ myhost.ddns.net, \"*.otherhost.ddns.net\" }";
              };

            };
          }
        ));
      };

    };
  };

  config = with builtins; let
    providersConf = lib.concatStrings (map (p: ''
      provider ${p.provider} {
          include("${p.passwordFile}")
          username = ${p.username}
          hostname = ${p.hostname}
      }
    '') (attrValues cfg.providers));

    configFile = providersConf + (let
    #   f = cfg.configFile;
      f = cfg.configFileContents;
    in lib.optionalString (f != null)
    #   "include(\"${f}\")\n"
      f
    );

  in mkIf cfg.enable {
    environment = {
      systemPackages = [ pkgs.inadyn ];
      etc."inadyn.conf".text = configFile;
    };

    systemd.services.inadyn = {
      documentation = [
        "man:inadyn"
        "man:inadyn.conf"
        "file:${pkgs.inadyn}/share/doc/inadyn/README.md"
      ];
      after = [ "network-online.target" ];
      requires = [ "network-online.target" ];
      serviceConfig = {
        ExecStart =
          "${pkgs.inadyn}/bin/inadyn --foreground " +
          "--config /etc/inadyn.conf " +
          (lib.optionalString (! builtins.isNull cfg.logLevel) "--loglevel ${cfg.logLevel} ") +
          "--cache-dir /var/cache/inadyn " +
          # "--pidfile /var/run/inadyn.pid" +
          "--no-pidfile " +
          "--drop-privs inadyn";
        WorkingDirectory = "/run/inadyn";
      };
      wantedBy = [ "multi-user.target" ];
    };
    systemd.tmpfiles.rules = [
      "d '/run/inadyn' 0750 inadyn inadyn - -"
      "d '/var/cache/inadyn' 0750 inadyn inadyn - -"
      "d '/var/lib/inadyn' 0750 inadyn inadyn - -"
    ];
    users = {
      users.inadyn = {
        description = "Non-root user for inadyn";
        group = "inadyn";
        isSystemUser = true;
      };
      groups.inadyn = {};
    };
  };
}
