{
  description = "A highly structured configuration database.";
  # Framework documentation: https://digga.divnix.com/index.html

  nixConfig = {
    extra-experimental-features = "nix-command flakes";
    extra-substituters = [
      "https://nrdxp.cachix.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nrdxp.cachix.org-1:Fc5PSqY2Jm1TrWfm88l6cvGWwz3s93c6IOifQWnhNW4="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    # Track channels with commits tested and built by hydra
    nixos.url = "github:nixos/nixpkgs/nixos-23.11";
    nixpkgs.follows = "nixos";
    latest.url = "github:nixos/nixpkgs/nixos-unstable";

    # For darwin hosts: it can be helpful to track this darwin-specific stable
    # channel equivalent to the `nixos-*` channels for NixOS. For one, these
    # channels are more likely to provide cached binaries for darwin systems.
    # But, perhaps even more usefully, it provides a place for adding
    # darwin-specific overlays and packages which could otherwise cause build
    # failures on Linux systems.
    nixpkgs-darwin-stable.url = "github:NixOS/nixpkgs/nixpkgs-22.11-darwin";

    digga.url = "github:divnix/digga";
    digga.inputs.nixpkgs.follows = "nixos";
    digga.inputs.nixlib.follows = "nixos";
    digga.inputs.home-manager.follows = "home";
    digga.inputs.deploy.follows = "deploy";

    home.url = "github:nix-community/home-manager/release-22.11";
    home.inputs.nixpkgs.follows = "nixos";

    darwin.url = "github:LnL7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs-darwin-stable";

    deploy.url = "github:serokell/deploy-rs";
    deploy.inputs.nixpkgs.follows = "nixos";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixos";

    nvfetcher.url = "github:berberman/nvfetcher";
    nvfetcher.inputs.nixpkgs.follows = "nixos";

    nixos-hardware.url = "github:nixos/nixos-hardware";

    #
    # Extra packages or modules that people have already done for me :)
    #

    # fake-hwclock to save & restore realtime on rasp pi, since it doesn't
    # have a realtime hw clock to persist walltime across boots otherwise
    fake-hwclock.url = "github:EHfive/flakes";
    fake-hwclock.inputs.nixpkgs.follows = "nixos";
    fake-hwclock.inputs.deploy-rs.follows = "deploy";
    fake-hwclock.inputs.home-manager.follows = "home";

    nix-portable.url = "github:virusdave/nix-portable";
    nix-portable.inputs.nixpkgs.follows = "nixos";
    # Pin the below one; it's floating upstream for some unknown reason...
    nix-portable.inputs.nix.url = "github:NixOS/nix/5c917c32048ef185ea0eec352c3505485aa3212c";
    nix-portable.inputs.nix.inputs.nixpkgs.follows = "nixos";
    # TODO(Dave): the `nix-portable.inputs.nix` input doesn't seem to
    # be being used currently.  Perhaps remove it completely?

    # TODO(Dave): Handle the other transitive inputs for the above?
  };

  outputs = {
    self,
    nixpkgs,
    # everything else
    agenix,
    deploy,
    digga,
    fake-hwclock,
    home,
    nix-portable,
    nixos,
    nixos-hardware,
    nur,
    nvfetcher,
    ...
  } @ inputs:
    digga.lib.mkFlake
    {
      inherit self inputs;

      channelsConfig = {allowUnfree = true;};

      channels = {
        nixos = {
          # TODO(Dave): Do `imports` here actually matter??
          imports = [(digga.lib.importOverlays ./overlays)];
          overlays = [ ];
        };
        nixos-with-overlays = {
          input = nixos;
          # TODO(Dave): Do `imports` here actually matter??
          imports = [(digga.lib.importOverlays ./overlays)];
          overlays = [
            # Get Rasp PI to retain clock value across reboots
            (final: prev: {
              inherit (fake-hwclock.packages."${prev.system}") fake-hwclock;
            })

            # Fix CPU accounting exporter, see:
            #  https://github.com/prometheus-community/systemd_exporter/issues/34
            (final: prev: {
              prometheus-systemd-exporter = prev.prometheus-systemd-exporter.overrideAttrs (me: rec {
                version = "0.5.0";
                src = final.fetchFromGitHub {
                  owner = "pelov";
                  repo = me.pname;
                  rev = "v${version}+cpu_stat1";
                  sha256 = "sha256-k1kkbZLzacbDnbX2YecNRr3w5iMxdkUPMigZqKQlJf8=";
                };
              });
            })

            (final: prev: {
              # nix = prev.nix.overrideAttrs (self: super: {
              #   patches = (super.patches or []) ++ [
              #     ./pkgs/patches/0001-Stop-hard-linking-non-directory-inputs-as-this-will-.patch
              #   ];
              # });

              nix-portable = let
                  ps = nix-portable.packages;
                  sys = ps."${prev.system}" or {};
                  np = sys.nix-portable or null;
                in np;
            })
          ];
        };
        nixpkgs-darwin-stable = {
          # TODO(Dave): Do `imports` here actually matter??
          imports = [(digga.lib.importOverlays ./overlays)];
          overlays = [
            # TODO(Dave): Figure out WTF the below does... :thinking_face:

            # TODO: restructure overlays directory for per-channel overrides
            # `importOverlays` will import everything under the path given
            (channels: final: prev:
              {
                inherit (channels.latest) mas;
              }
              // prev.lib.optionalAttrs true {})
          ];
        };
        latest = {};
      };

      lib = import ./lib {lib = digga.lib // nixos.lib;};

      # TODO(Dave): Does this even work???
      sharedOverlays = [
        (final: prev: {
          __dontExport = true;
          lib = prev.lib.extend (lfinal: lprev: {
            our = self.lib;
          });
        })

        # TODO(Dave): Are these needed (or wanted even)?
        nur.overlay
        agenix.overlay
        nvfetcher.overlay

        (import ./pkgs)
      ];

      nixos = {
        hostDefaults = {
          system = "x86_64-linux";
          channelName = "nixos-with-overlays";
          imports = [(digga.lib.importExportableModules ./modules)];
          modules = [
            {lib.our = self.lib;}
            digga.nixosModules.bootstrapIso
            digga.nixosModules.nixConfig
            home.nixosModules.home-manager
            agenix.nixosModules.age

            # TODO(Dave): Would love to be able to put this into the host-specific location!
            fake-hwclock.nixosModules.fake-hwclock
          ];
        };

        imports = [(digga.lib.importHosts ./hosts/nixos)];
        hosts = {
          # set host-specific properties here
          arm-builder-west.system = "aarch64-linux";
          lidjamoypi.system = "aarch64-linux";
          stagingfreshlybakednyc.system = "aarch64-linux";
          wwwfreshlybakednyc.system = "aarch64-linux";
        };
        importables = rec {
          profiles =
            digga.lib.rakeLeaves ./profiles
            // {
              users = digga.lib.rakeLeaves ./users;
            };
          suites = with profiles; rec {
            base = [core.nixos users.nixos users.root];
          };
        };
      };

      darwin = {
        hostDefaults = {
          system = "x86_64-darwin";
          channelName = "nixpkgs-darwin-stable";
          imports = [(digga.lib.importExportableModules ./modules)];
          modules = [
            {lib.our = self.lib;}
            digga.darwinModules.nixConfig
            home.darwinModules.home-manager
            agenix.nixosModules.age
          ];
        };

        imports = [(digga.lib.importHosts ./hosts/darwin)];
        hosts = {
          # set host-specific properties here
          Mac = {};
        };
        importables = rec {
          profiles =
            digga.lib.rakeLeaves ./profiles
            // {
              users = digga.lib.rakeLeaves ./users;
            };
          suites = with profiles; rec {
            base = [core.darwin users.darwin];
          };
        };
      };

      home = {
        imports = [(digga.lib.importExportableModules ./users/modules)];
        modules = [];
        exportedModules = [];
        importables = rec {
          profiles = digga.lib.rakeLeaves ./users/profiles;
          suites = with profiles; rec {
            base = [direnv git];
          };
        };
        users = {
          # TODO: does this naming convention still make sense with darwin support?
          #
          # - it doesn't make sense to make a 'nixos' user available on
          #   darwin, and vice versa
          #
          # - the 'nixos' user might have special significance as the default
          #   user for fresh systems
          #
          # - perhaps a system-agnostic home-manager user is more appropriate?
          #   something like 'primaryuser'?
          #
          # all that said, these only exist within the `hmUsers` attrset, so
          # it could just be left to the developer to determine what's
          # appropriate. after all, configuring these hm users is one of the
          # first steps in customizing the template.
          nixos = {suites, ...}: {
            imports = suites.base;

            home.stateVersion = "22.11";
          };
          darwin = {suites, ...}: {
            imports = suites.base;

            home.stateVersion = "22.11";
          };
        }; # digga.lib.importers.rakeLeaves ./users/hm;
      };

      #devshell = ./shell;

      # TODO: similar to the above note: does it make sense to make all of
      # these users available on all systems?
      #homeConfigurations =
      #  digga.lib.mergeAny
      #  (digga.lib.mkHomeConfigurations self.darwinConfigurations)
      #  (digga.lib.mkHomeConfigurations self.nixosConfigurations);

      deploy.nodes = digga.lib.mkDeployNodes self.nixosConfigurations {};
    };
}
