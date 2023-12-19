{ modulesPath, lib, pkgs, options, config, ... }:

let
  inherit (lib) mkOption types mkIf mdDoc;
  cfg = config.services.wordpressWithPluginState;
  sites = cfg.sites;
  cfgWp = config.services.wordpress;
  optsWp = options.services.wordpress;

  allSites = lib.attrNames sites;
  mappedPlugins = lib.attrNames cfg.stateContentDirMapping;

  statePath = site: plugin: "/var/lib/wordpress/${site}-plugins-state/${plugin}";

in {
  options.services.wordpressWithPluginState = with types; optsWp // {
    stateContentDirMapping = mkOption {
      default = {};
      type = attrsOf str;
      description = mkDoc ''
        Mapping of "[plugin name] to [name of link within the `wp-content` directory to point to plugin state dir]
      '';
      example = "{duplicator = \"backups-dup-lite\";}";
    };
  };

  config = mkIf (sites != {}) (
    # Implementation notes:
    #
    # The base service is built from a few layers:
    #  - First, the wordpress package *itself* is a derivation
    #  - Second, each plugin that is anywhere referenced is a derivation
    #  - Third, a per-site package is created that copies the first two
    #    into place.
    #  - Finally, in our wrapping service, we override the wordpress
    #    package used in step one to pre-create some per-{plugin X site}
    #    symlinks in step one.

    # mkMerge [{ }]
    let
      withSymlinksForSite = wordpress: site: pluginsToPaths: pkgs.stdenvNoCC.mkDerivation {
        pname = "wordpress-${site}-with-plugin-state-links";
        src = wordpress;
        version = wordpress.version;
        installPhase = ''
          mkdir -p $out
          cp -r * $out/

          mkdir -p $out/share/wordpress/wp-content
          ${(lib.concatMapStringsSep
            "\n"
            (plugin: ''ln -s "${statePath site plugin}" "$out/share/wordpress/wp-content/${cfg.stateContentDirMapping.${plugin}}"'')
            mappedPlugins)}
        '';
      };
    in {
      systemd.tmpfiles.rules =
        lib.mkAfter (lib.forEach (lib.cartesianProductOfSets {
          plugin = mappedPlugins;
          site = allSites;
        }) (p: "d '${statePath p.site p.plugin}' 0700 wordpress ${config.services.${cfg.webserver}.group} - -"));

      services.wordpress.sites =
        lib.mapAttrs (k: v: (v // {
          package = (withSymlinksForSite v.package k cfg.stateContentDirMapping);
        })) sites;
      services.wordpress.webserver = cfg.webserver;
    }
  );
}