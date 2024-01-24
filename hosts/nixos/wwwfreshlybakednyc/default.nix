{ config, inputs, pkgs, lib
, modulesPath
, ...
}:

let
  secrets = with lib; (flip genAttrs) (n: {
    plain = config.age.secrets.${n}.path;
    cipher = ./secrets/${n}.age;
  }) [
    # "inadyn-password"

    "test-secret"
  ];

  freshlyBakedDomain = "freshlybaked.nyc";
  hostname = "wwwfreshlybakednyc";
  vimCustom = pkgs.vim_configurable.customize {};

  notifyMe = pkgs.writeShellScriptBin "notify" ''
    ${pkgs.apprise}/bin/apprise -v -t "Heads up from $(${pkgs.hostname}/bin/hostname)..." -b \
      "$*" \
      'json://ntfy.sh/?+X-Priority=high&:topic=vd420__notify_01' \
      'mailto://dave.nicponski:qlnllemibmyjccyv@gmail.com?from=Dave%20Alerts<dave.nicponski@gmail.com>&to=dave.nicponski@gmail.com'
  '';

  makeSiteWriteable = let
    site = "${freshlyBakedDomain}";
    loc = config.services.nginx.virtualHosts."${site}".root;
  in pkgs.writeShellScriptBin "make-wordpress-site-writeable" ''
    set -ex
    mount -t overlay overlay \
      -o lowerdir=${loc},upperdir=/var/lib/wordpress/overlay/upper,workdir=/var/lib/wordpress/overlay/workdir \
      ${loc}
    chown wordpress:nginx ${loc}
  '';
in {
  imports = [
    "${modulesPath}/virtualisation/amazon-image.nix"
  ];

  age.secrets = with lib; recursiveUpdate (mapAttrs (n: v: {file = v.cipher;}) secrets) {
    # Per-secret overrides go here
    # inadyn-password.owner = "inadyn";  # what user does it run as?
  };

  ec2.hvm = true;
  ec2.efi = true;

  environment.shells = with pkgs; [
    bashInteractive
  ];
  environment.shellAliases = {
      l = "${pkgs.eza}/bin/eza -lag --color=always";
      ls = "${pkgs.eza}/bin/eza -ag --color=always";

      less = "less -R";
      LESS = "less -R --no-lessopen";

      watch = "viddy";
  };
  environment.systemPackages = with pkgs; [
    bash-completion
    bashInteractive
    bat
    compsize # compression stats for btrfs
    eza
    fx
    gitMinimal
    #hexyl
    htop
    inetutils
    libcgroup
    lsof
    memtree
    ncdu
    silver-searcher
    viddy # better `watch`
    #vimCustom
    vim
  ] ++ [
    # Dave's additions
    makeSiteWriteable
    notifyMe
  ];

  # Compressed BTRFS subvolume mounts
  fileSystems."/" = lib.mkForce {
    device = "/dev/disk/by-label/nixos-btrfs-fbweb";
    fsType = "btrfs";
    options = [
      "compress=zstd:3" "subvol=root"
      "nossd"
    ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-label/nixos-btrfs-fbweb";
    fsType = "btrfs";
    options = [
      "noatime"
      "compress=zstd:3" "subvol=nix"
      "nossd"
    ];
  };

  # These are huge!  Do we actually NEED them?  The non-flake system config seems
  # like it didn't include these at all!
  hardware.enableRedistributableFirmware = false;

  networking.firewall = {
    allowedTCPPorts = [
      80 443  # nginx
    ];
    allowedUDPPorts = [ ];
  };
  networking.hostName = hostname;

  nix.generateRegistryFromInputs = false;
  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "dave" ];
  };

  programs.mosh.enable = true;

  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [
      better-mouse-mode
      continuum
      fuzzback  # Maybe, if deps aren't too heavyweight
      pain-control
      resurrect
      sensible

      tmux-thumbs
    ];
    terminal = "screen-256color";
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "dave.nicponski+acme.certs@gmail.com";
  };

  services.nginx = {
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;

    # GRRRrrr...  These seem to be used in the install directory path, sadly.
    virtualHosts."${freshlyBakedDomain}" = {
      enableACME = true;
      forceSSL = true;
      serverAliases = [ "www.${freshlyBakedDomain}" ];
    };
  };

  services.journald.extraConfig = ''
    SystemMaxUse=150M
    SystemMaxFileSize=15M
  '';

  services.wordpressWithPluginState = let
    defaultPluginRevision = "3012590";
    defaultThemeRevision = "214891";

    extra = {
      plugins = (lib.mapAttrs (k: v: v // { rev = v.rev or defaultPluginRevision; }) {
        age-gate = {
          version = "3.2.0";
          sha256 = "sha256-Qv1YX0zMnqs8KhpFqs6sSe0sXo2kNqGg9X8Jpo6Man8=";
        };

        blog2social = {
          version = "7.3.4";
          sha256 = "sha256-q50RTKGpH4Cwmk96zFjUzXtNo6htly8pqFEPcbuwQI4=";
        };

        fullwidth-templates = {
          version = "1.1.1";
          sha256 = "sha256-JrYnCHeWkfA9J2Chj5NjRgkXuOQMqAXmvlrTgR59pvs=";
        };

        ##################################################
        # Site building with Elementor
        elementor = {
          version = "3.18.3";
          sha256 = "sha256-gcGwdiTMTkfFSSYzBM6xIvx29YVASZOMndMn4Qq4wzA=";
          patches = [
            (pkgs.fetchurl {
              name = "always-pro";
              url = "https://github.com/virusdave/elementor/commit/e8e699a1e00411fce2e8bf21d18f70e472d25b0a.patch";
              hash = "sha256-woMJRMLDDNxTu0HT+tHHPxLEjgzab1zO0Jk/9ZNl668=";
            })
          ];
        };

        essential-addons-for-elementor-lite = {
          version = "5.9.3";
          sha256 = "sha256-GupA1U4f/7Kkgle6m40XeS9BMGhSFCYrjV59Yl0ADLA=";
        };

        header-footer-elementor = {
          version = "1.6.22";
          sha256 = "sha256-gZVSRxaIwwE62pbo8LB+Ut3HQ6fOd/DEJHKaqBKPfJI=";
        };

        unlimited-elements-for-elementor = {
          version = "1.5.88";
          sha256 = "sha256-giAT70eYLolL1atxN2gx4i+YiYTB9KRVXYDv9X352v4=";
        };

        ##################################################
        # Site building with Kadence (free Elementor alternative)
        kadence-blocks = {
          version = "3.1.26";
          sha256 = "sha256-0NlSPoNrIs2OPhTvfW/nCBNVV68E8dW+o6zj0ds0n7g=";
        };

        #########################
        # Site backups.
        duplicator = {
          version = "1.5.7.1";
          sha256 = "sha256-js1gUbIO3h0c4G7YJPCbGK5uwP6n6WWnioMZUh/homs=";
        };

        ##################################################
        # Data collection
        optinmonster = {
          version = "2.15.1";
          sha256 = "sha256-dni6XwJMzEws0ErLMJRPig9KlJ+1LuWvqYzURJ3jJYM=";
        };
        wpforms-lite = {
          version = "1.8.5.3";
          sha256 = "sha256-dXKpsChEa34Vc/JVa4RF0xxhwlA9TQMD7Fg294PlRPY=";
        };

        #########################
      });
      themes = {
        # NOTA BENE: Must be present even if empty for `hackForThirdParty` to work..  :(
        # TODO(dave): Fix this.  This sucks!
      };
    };

    hackForThirdpartyPackages = {
      # Copied from `pkgs/servers/web-apps/wordpress/packages/thirdparty.nix` until this lands or can be patched in:
      # https://github.com/NixOS/nixpkgs/pull/275751
      plugins.civicrm = pkgs.fetchzip rec {
        name = "civicrm";
        version = "5.56.0";
        url = "https://storage.googleapis.com/${name}/${name}-stable/${version}/${name}-${version}-wordpress.zip";
        hash = "sha256-XsNFxVL0LF+OHlsqjjTV41x9ERLwMDq9BnKKP3Px2aI=";
      };
      plugins.elementor-pro = pkgs.fetchzip rec {
        name = "elementor-pro";
        version = "3.18.3";  # is this ok?  Copied from above.
        # url = "https://my.elementor.com/?download_file=14283270&order=wc_order_PgvZ1QIv1wRbj&uid=f4e4886cf7764dc03ce56f665ea4c50fd2c9b356c96f28db9dc591785867db6d&key=801e3aaf-2b4e-46d0-907d-88cc4a14f4a7&email=dave.nicponski@gmail.com";  # Saved to my Google Drive below
        url = "https://drive.usercontent.google.com/uc?id=1Prrruv6wFp6XIcha23RMEnwQUZqpNaro&export=download";
        hash = "sha256-kNkvZEYXeZgkhLWcvDf7VCC2eoSwgp2+4J5ISzSEf3E=";
        extension = "zip";
      };
      themes.geist = pkgs.fetchzip rec {
        name = "geist";
        version = "2.0.3";
        url = "https://github.com/christophery/geist/archive/refs/tags/${version}.zip";
        hash = "sha256-c85oRhqu5E5IJlpgqKJRQITur1W7x40obOvHZbPevzU=";
      };
      themes.kadence = pkgs.fetchzip rec {
        name = "kadence";
        version = "1.1.51";
        url = "https://downloads.wordpress.org/theme/kadence.${version}.zip";
        hash = "sha256-GugjLYNfm5vx2U8lnKONe8iqS/9LJMh6AFXSGnOFSBQ=";
      };
    };

    wpp = pkgs.wordpressPackages.extend (self: super:
      lib.mapAttrs (typePlural: v: (
        super."${typePlural}".extend (_: _:
          lib.recursiveUpdate (lib.mapAttrs (pname: data:
            (pkgs.wordpressPackages.mkOfficialWordpressDerivation {
              inherit pname;
              type = lib.removeSuffix "s" typePlural;
              data = data // { path = "${pname}/tags/${data.version}"; };
            }).overrideAttrs (self: super: (builtins.removeAttrs data ["type" "pname" "version" "passthru"]))
          ) v) (hackForThirdpartyPackages.${typePlural} or {})
        )
      )) extra);

  in rec {
    stateContentDirMapping.duplicator = "backups-dup-lite";
    stateContentDirMapping.elementor-uploads = "elementor_uploads";

    # TODO(dave): This is used for debugging wordpress site packages and themes.
    # Should be innocuous, but remove it eventually.
    test = {
      wpp = wpp;
      origWpp = pkgs.wordpressPackages;
      extra = extra;
    };

    sites."${freshlyBakedDomain}" = {
      #####
      # Debugging stuff here...
      extraConfig = ''
        # @ini_set( 'display_errors', 1 );
        @ini_set('memory_limit', '256M');
      '';
      #####

      database = {
        createLocally = true;
        name = "wp_freshlybaked";
        tablePrefix = "wp_fb_";
      };

      plugins = {
        inherit (wpp.plugins)
          antispam-bee
          async-javascript
          # civicrm
          # code-syntax-block
          disable-xml-rpc
          lightbox-photoswipe
          merge-minify-refresh  # Possibly disable if it causes problems
          opengraph  # For better embedded links in social media sites
          simple-login-captcha
          wordpress-seo
          wp-fastest-cache  # Might want to modify .htaccess, perhaps needs manual help?
          wp-statistics
        ;
      } // {
        # TODO(Dave): Consider auto-populating this list starting with the above manually
        # specified and installed plugins by default.

        inherit (wpp.plugins)
          ##########
          # Manually added items...
          blog2social

          # Site editing
          elementor
          elementor-pro
          essential-addons-for-elementor-lite
          fullwidth-templates
          header-footer-elementor
          kadence-blocks
          unlimited-elements-for-elementor

          # Compliance
          age-gate  # TODO(Dave): Push this upstream.  # TODO(Dave): What do you mean "upstream" here?

          # Site Backups
          duplicator

          # Data collection
          optinmonster
          wpforms-lite
        ;
      };

      themes = {
        inherit (wpp.themes)
          kadence
          twentytwentytwo
          twentytwentythree;
      };
    };

    webserver = "nginx";
  };

  systemd.services.notify-system-power-cycle = {
    serviceConfig = {
      Type = "oneshot";
      TimeoutSec = 60;
      RemainAfterExit = "yes";
    };

    description = "Notify Dave when this system is starting up";

    after = [ "network-online.target" ];
    requires = [ "network-online.target" ];
    before = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
  };
  systemd.services.notify-system-power-cycle.serviceConfig.ExecStart =
    ''${notifyMe}/bin/notify "FYI: System (${hostname}) is apparently starting up"'';
  systemd.services.notify-system-power-cycle.serviceConfig.ExecStop =
    ''${notifyMe}/bin/notify "FYI: System (${hostname}) is apparently shutting down"'';

  swapDevices = [
    { device = "/dev/disk/by-uuid/716907b0-c867-4a0b-b2f6-ff3a9e26a6e1"; }  # 800MB
    { device = "/dev/disk/by-uuid/7a24fb96-5f0d-410f-b0d3-a38657824dbb"; }  # 1GB
  ];
  system.stateVersion = "22.05";  # NB: Do not change this unless you KNOW what you're doing!

  systemd.tmpfiles.rules = [
    "d '/var/lib/wordpress/overlay' 0750 wordpress nginx - -"
    "d '/var/lib/wordpress/overlay/upper' 0750 wordpress nginx - -"
    "d '/var/lib/wordpress/overlay/workdir' 0750 wordpress nginx - -"
  ];

  # Add `dave` as a user.
  users = {
    mutableUsers = false;

    users."dave" = {
      createHome = true;
      extraGroups = [ "wheel" "audio" "video" "tty" "adm" "messagebus" "input" "render" "podman" ]; # Enable ‘sudo’ for the user.
      hashedPassword = "$y$j9T$4R36MYOFnwVVLvb6hHml1.$qacBsg3r9.hU/uy0WNOjxgL7KfZu7B016gSRvtzUNL9";
      home = "/home/dave";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCi+GbiMk0UqGYfG+7jmTGaKRtIVTFBwVG0p6kg3l4rsG2S7LCBG9MAgMQQKCfBay1SdXVZvr8wrc7TMj2dk0ZrnQklBd7Cn6hXE3rOiIa+1FFAtXfI4r6gMhzIa91uF63okW09wPYCUxUYmhNSGwC1rTytU5SE1jf5o/Asp/ZfHvmxhm5EUxw5qacS/Ilf4OhEWyQaQG6xeHnO4NCGThIpdTxC2Q9LpQAPlz6lZedEWTTLcXRTcG+olhxfudQ/JMdzQhqluVRCOgolIS32rvKi9st7H3D6q2sZH8MNnbl22FQNHg8f4fl34L1X/n/Zf6573eL0V5uKEtdachwrN+X5FUgwwzn7ivHjAxOHVHuWuADk+HVCG95zN1eyPLbCR8FwF/LtfjfQiF6Erwd3mNdjMK9J1upAfZkix7Ap8UDi2qmK5fzWNXcvFV7bFSo8kRd7ztMRUzHU7iTynRBUGhQel0+S27oMkOrf8yucvEWwf6dq064IleQEjronyweUmLgcSIWrxZJcLohnruleJzSz1MngZ8lsccMNGQys1D1ycayYirMFqBneNnRPtpaqesy9aADvxyzCvp69DogeJEfe++FGGVaKijxRc//EwCqqSyaie+eH1+eVMva+QN3G3yjNgIiNo3ztc60hqQq0sG/K447zHuyr5xFc54fYFv2ZwQ== dave.nicponski@gmail.com"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC6P8roQA7hkbzFM8RqDY8DDkwfg+GbVzilBWjF6L8urodwkXtGPGIf/uyP18bC+ceYRyYbYRAeynVpueNPkcWQUf0GzvBXVkO6bHc7/M6Dj8VYe3v/lgeb6fyVRiI7khsS1ra37asPCOLxLqzYUh8+ml5tzmED3dwpgPcULw0/jnRaKlzJ/TNaDAI1u69FBbDswblNhFqSoQq1C6nUHb2hf9Zegb3FHwy4pE3LVvxqZiVj1z0zlrNVWHYM/LN4sihp9n81llHGDLa0ReZiYkgPBgvTn90XKbZ/gI3RuxYL52cxUohP2r+P4G2nIvaJK4SK9quEIXYhro7dJRz6h3SV dave.nicponski@gmail.com chromebook"
      ];
    };
  };
}
