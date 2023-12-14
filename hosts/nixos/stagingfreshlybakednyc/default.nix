# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, inputs, pkgs, lib
, modulesPath
, ...
}:

let
  secrets = with lib; (flip genAttrs) (n: {
    plain = config.age.secrets.${n}.path;
    cipher = ./secrets/${n}.age;
  }) [
    "inadyn-password"

    "test-secret"
  ];

  changedetection-io-port = 5000;
  freshlyBakedDomain = "freshlybaked.nyc";
  hostname = "stagingfreshlybakednyc";
  vimCustom = pkgs.vim_configurable.customize {};

  notifyMe = pkgs.writeShellScriptBin "notify" ''
    ${pkgs.apprise}/bin/apprise -v -t "Heads up from $(${pkgs.hostname}/bin/hostname)..." -b \
      "$*" \
      'json://ntfy.sh/?+X-Priority=high&:topic=vd420__notify_01' \
      'mailto://dave.nicponski:qlnllemibmyjccyv@gmail.com?from=Dave%20Alerts<dave.nicponski@gmail.com>&to=dave.nicponski@gmail.com'
  '';

  makeSiteWriteable = let
    site = "staging.${freshlyBakedDomain}";
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
    inadyn-password.owner = "inadyn";  # what user does it run as?
  };

  ec2.hvm = true;
  ec2.efi = true;

  environment.shells = with pkgs; [
    bashInteractive
  ];
  environment.shellAliases = {
      l = "${pkgs.eza}/bin/eza -la --color=always";
      ls = "${pkgs.eza}/bin/eza -a --color=always";

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
    lsof
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
      53  # iodine
    ];
    allowedUDPPorts = [ 53 ];  # iodine
    allowedUDPPortRanges = [
      { from = 60000; to = 61000;}  # Mosh
    ];
  };
  networking.hostName = hostname;

  nix.generateRegistryFromInputs = false;
  nix.settings = {
    auto-optimise-store = true;
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "dave" ];
  };

  nixpkgs.overlays = [
    # Disable this package to save some disk space.  We can't just not include this package
    # on disk easily, since we're (ab)using the nixos service definition to do most of the
    # necessary system config (setup users, directories, etc) for us, even though we're
    # _actually_ using a containerized process for this (by disabling the systemd unit for
    # the nixos service).
    (final: prev: { changedetection-io = pkgs.eza.man; })  # a TINY package, ~7KB

    # # qt5webkit is marked as insecure in 23.11, and we cannot use `nixpkgs.config` to
    # # individually enable just this package.
    # (final: prev: { qt5.qtwebkit.meta.insecure = false; })
  ];

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

  ##########################################
  # Watch webpages for changes
  services.changedetection-io = {
    enable = true;
    baseURL = "https://sitechanges.dave.nicponski.dev/";
    port = changedetection-io-port;  # Defaults to port 5000

    playwrightSupport = true;
    # webDriverSupport = true;  # Enable to use headless Chromium for rendering
  };
  virtualisation.oci-containers.containers = lib.mkMerge [
    (lib.mkIf config.services.changedetection-io.webDriverSupport {
      # Tacky fix for using the docker images on ARM
      changedetection-io.dependsOn = [ "changedetection-io-webdriver" ];
      changedetection-io.environment.WEBDRIVER_URL = "localhost:4444";
      changedetection-io-webdriver.image =
        lib.mkForce "seleniarm/standalone-chromium";  # TODO(Dave): Pin version!
    })
    (lib.mkIf config.services.changedetection-io.playwrightSupport {
      changedetection-io.dependsOn = [ "changedetection-io-playwright" ];
      changedetection-io.environment.DEBUG = "-browserless:chrome-helper*,browserless:server";  # Disable log spam
      changedetection-io.environment.PLAYWRIGHT_DRIVER_URL =
        "ws://localhost:4444/?stealth=1&--disable-web-security=true";
      # Limit resource consumption, as this container is kinda heavyweight
      changedetection-io-playwright.extraOptions = [ "--cpu-shares=512" "--memory=512m" ];
      changedetection-io-playwright.image =
        lib.mkForce
          # "browserless/chrome:arm64";  # Version pinned below
          "docker.io/browserless/chrome@sha256:84ff67d7976d9e7bcc08ced21479fa4cbb0063f5c514fb56d6fd2ddb98c6b350";
    })
    {
      changedetection-io = {
        # image = "dgtlmoon/changedetection.io";  # Version pinned below
        image = "docker.io/dgtlmoon/changedetection.io@sha256:23806e96a79724891fb9fa998244fd376c7f2c3e6ae99e5514e63fb203bf6d32";

        environment.BASE_URL = "https://sitechanges.dave.nicponski.dev/";
        environment.HIDE_REFERER = "true";
        environment.USE_X_SETTINGS = "1";
        extraOptions = [
          "--network=host"  # Needs to see the other container, and for some reason it didn't see it without this.
          "--cpu-shares=768"  # Keep system otherwise responsive.
        ];
        ports = [ "127.0.0.1:5000:5000" ];
        volumes = [ "/var/lib/changedetection-io:/datastore" ];
      };
    }
  ];
  systemd.services.changedetection-io.enable = false;
  # Sacrifice the change-detection services if we run out of RAM.  They can be... resource hungry...
  systemd.services."podman-changedetection-io" = lib.mkIf config.services.changedetection-io.enable { serviceConfig.OOMScoreAdjust=500; };
  systemd.services."podman-changedetection-io-playwright" = lib.mkIf config.services.changedetection-io.playwrightSupport { serviceConfig.OOMScoreAdjust=501; };
  systemd.services."podman-changedetection-io-webdriver" = lib.mkIf config.services.changedetection-io.webDriverSupport { serviceConfig.OOMScoreAdjust=501; };
  systemd.tmpfiles.rules = [
    "d '/var/lib/changedetection-io' 0750 changedetection-io changedetection-io - -"

    ""
    "d '/var/lib/wordpress/overlay' 0750 wordpress nginx - -"
    "d '/var/lib/wordpress/overlay/upper' 0750 wordpress nginx - -"
    "d '/var/lib/wordpress/overlay/workdir' 0750 wordpress nginx - -"
  ];
  ##########################################


  # TODO(Dave): Eventually, set this up to automatically keep the production
  # server's DNS entry up to date as well.
  services.networking.inadyn = {
    enable = true;

    configFileContents = ''
      period = 60
      user-agent = Mozilla/5.0

      custom namecheap {
        username = freshlybaked.nyc
        include("${secrets.inadyn-password.plain}")
        ddns-server = dynamicdns.park-your-domain.com
        ddns-path = "/update?domain=%u&password=%p&host=%h&ip=%i"
        hostname = { "staging" }
      }
     '';
  };

  services.nginx = let
    defaults = {
      basicAuth = {
        dave = "letmein";
        pam = "letmein";
      };
      enableACME = true;
      forceSSL = true;
    };
  in {
    #####
    # Debugging
    logError = "stderr debug";
    #####

    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;

    # GRRRrrr...  These seem to be used in the install directory path, sadly.
    # virtualHosts."${freshlyBakedDomain}" = {
    #   enableACME = true;
    #   forceSSL = true;
    #   serverAliases = [ "www.${freshlyBakedDomain}" ];
    # };

    virtualHosts."crm.staging.${freshlyBakedDomain}" = defaults // {
      serverAliases = [ "staging.crm.${freshlyBakedDomain}" ];
    };

    virtualHosts."sitechanges.dave.nicponski.dev" = defaults // {
      basicAuth = { dave = "letmein"; };
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString changedetection-io-port}";
        proxyWebsockets = true; # needed if you need to use WebSocket
      };
    };

    virtualHosts."staging.${freshlyBakedDomain}" = defaults // {
      serverAliases = [ "www.staging.${freshlyBakedDomain}" ];
    };
  };

  services.journald.extraConfig = ''
    SystemMaxUse=150M
    SystemMaxFileSize=15M
  '';

  services.odoo = {
    enable = true;
    domain = "crm.staging.${freshlyBakedDomain}";
    settings.options = {
      limit_memory_soft = 536870912;  # 512MB
      limit_memory_hard = 1073741824;  # 1GB
      max_cron_threads = 1;
      #workers = 2;
    };
  };

  services.wordpressWithPluginState = let
    ai1Name = "ai1wm-backups";
    defaultRevision = "3012590";

    extra = /*(lib.recursiveUpdate*/ {
    plugins = (lib.mapAttrs (k: v: v // { rev = v.rev or defaultRevision; }) {
      age-gate = {
        version = "3.2.0";
        sha256 = "sha256-Qv1YX0zMnqs8KhpFqs6sSe0sXo2kNqGg9X8Jpo6Man8=";
      };

      elementor = {
        version = "3.18.2";
        sha256 = "sha256-O0f5ngjykALcYUVddZgJx6BBKkx1T47YRUmpM6tc1YA=";
        patches = [
          (pkgs.fetchurl {
            name = "always-pro";
            url = "https://github.com/virusdave/elementor/commit/e8e699a1e00411fce2e8bf21d18f70e472d25b0a.patch";
            hash = "sha256-woMJRMLDDNxTu0HT+tHHPxLEjgzab1zO0Jk/9ZNl668=";
          })
        ];
      };

      #########################
      # Site backups.
      all-in-one-wp-migration = rec {
        version = "7.79";
        sha256 = "sha256-eyWIupl96qG2oz0tjGMGKKH8++yTvW3V1+mcr9/i/wA=";
        postInstall = "ln -s ../../${ai1Name}-storage $out/storage";
      };

      backup-backup = {
        version = "1.2.9";
        sha256 = "sha256-tKco8umdPIzdurQdCeOeNMLfMpb7Jgk6YohQHq+sPgM=";
      };

      blog2social = {
        version = "7.3.4";
        sha256 = "sha256-q50RTKGpH4Cwmk96zFjUzXtNo6htly8pqFEPcbuwQI4=";
      };

      duplicator = {
        version = "1.5.7.1";
        sha256 = "sha256-js1gUbIO3h0c4G7YJPCbGK5uwP6n6WWnioMZUh/homs=";
      };

      updraftplus = {
        version = "1.23.9";
        sha256 = "sha256-rb+FF/AOH8zQNTUKi13dv2vamlIHgNc0al4qcq+qJkc=";
      };
      #########################
    });
    } /*hackForThirdpartyPackages)*/;

    hackForThirdpartyPackages = {
      # Copied from `pkgs/servers/web-apps/wordpress/packages/thirdparty.nix` until this lands or can be patched in:
      # https://github.com/NixOS/nixpkgs/pull/275751
      plugins.civicrm = pkgs.fetchzip rec {
        name = "civicrm";
        version = "5.56.0";
        url = "https://storage.googleapis.com/${name}/${name}-stable/${version}/${name}-${version}-wordpress.zip";
        /*hash*/ sha256 = "sha256-XsNFxVL0LF+OHlsqjjTV41x9ERLwMDq9BnKKP3Px2aI=";
      };
      themes.geist = pkgs.fetchzip rec {
        name = "geist";
        version = "2.0.3";
        url = "https://github.com/christophery/geist/archive/refs/tags/${version}.zip";
        /*hash*/ sha256 = "sha256-c85oRhqu5E5IJlpgqKJRQITur1W7x40obOvHZbPevzU=";
      };
    };

    wpp = pkgs.wordpressPackages.extend (self: super:
      lib.mapAttrs (typePlural: v: (
        super."${typePlural}".extend (_: _:
          lib.mapAttrs (pname: data:
            (pkgs.wordpressPackages.mkOfficialWordpressDerivation {
              inherit pname;
              type = lib.removeSuffix "s" typePlural;
              data = data // { path = "${pname}/tags/${data.version}"; };
            }).overrideAttrs (self: super: (builtins.removeAttrs data ["type" "pname" "version" "passthru"]))
          ) v
        )
      )) extra);

  in rec {
    stateContentDirMapping.all-in-one-wb-migration = ai1Name; # "ai1wm-backups";
    stateContentDirMapping.all-in-one-wb-migration-storage = "${ai1Name}-storage";
    stateContentDirMapping.backup-migration = "backup-migration";
    stateContentDirMapping.duplicator = "backups-dup-lite";
  test = {
    wpp = wpp;
    origWpp = pkgs.wordpressPackages;
    extra = extra;
  };

    sites."staging.${freshlyBakedDomain}" = {
      #####
      # Debugging stuff here...
      extraConfig = ''
        # @ini_set( 'display_errors', 1 );
      '';
      settings = {
        WP_DEBUG = true;
        WP_DEBUG_LOG = "/tmp/wp-errors.log";
        WP_DEBUG_DISPLAY = false;
      };
      #####

      database = {
        createLocally = true;
        name = "wp_staging_freshlybaked";
        tablePrefix = "wp_staging_fb_";
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
          elementor

          # Compliance
          age-gate  # TODO(Dave): Push this upstream.  # TODO(Dave): What do you mean "upstream" here?

          # Site Backups
          all-in-one-wp-migration
          backup-backup
          duplicator
          updraftplus
        ;
      };

      themes = { inherit (wpp.themes) twentytwentytwo twentytwentythree; };

    };

    webserver = "nginx";
  };

  systemd.services.notify-system-power-cycle = {
    serviceConfig = {
      Type = "oneshot";
      TimeoutSec = 60;
      # ExecStart = ''${pkgs.apprise}/bin/apprise -v -t \"System starting up\" -b \"FYI: System (${hostname}) is starting up\" 'json://ntfy.sh/?+X-Priority=high&:topic=vd420__notify_01' '';
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

  # TODO(Dave): These two should probably be conditioned on the service being enabled :thinking_face:
  systemd.services.restart-changedetection-containers = {
    description = "Restart changedetection-io-playwright";
    script = "systemctl restart 'podman-changedetection-io*.service'";
    serviceConfig.Type = "oneshot";
  };
  systemd.timers.restart-changedetection-containers-timer = {
    description = "Periodically restart changedetection-io-playwright";
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "hourly";
    timerConfig.Unit = "restart-changedetection-containers.service";
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/716907b0-c867-4a0b-b2f6-ff3a9e26a6e1"; }  # 800MB
    { device = "/dev/disk/by-uuid/1681190b-4f65-4ce0-9244-e6436a26735a"; }  # 1GB
  ];
  system.stateVersion = "22.05";  # NB: Do not change this unless you KNOW what you're doing!

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
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCi+GbiMk0UqGYfG+7jmTGaKRtIVTFBwVG0p6kg3l4rsG2S7LCBG9MAgMQQKCfBay1SdXVZvr8wrc7TMj2dk0ZrnQklBd7Cn6hXE3rOiIa+1FFAtXfI4r6gMhzIa91uF63okW09wPYCUxUYmhNSGwC1rTytU5SE1jf5o/Asp/ZfHvmxhm5EUxw5qacS/Ilf4OhEWyQaQG6xeHnO4NCGThIpdTxC2Q9LpQAPlz6lZedEWTTLcXRTcG+olhxfudQ/JMdzQhqluVRCOgolIS32rvKi9st7H3D6q2sZH8MNnbl22FQNHg8f4fl34L1X/n/Zf6573eL0V5uKEtdachwrN+X5FUgwwzn7ivHjAxOHVHuWuADk+HVCG95zN1eyPLbCR8FwF/LtfjfQiF6Erwd3mNdjMK9J1upAfZkix7Ap8UDi2qmK5fzWNXcvFV7bFSo8kRd7ztMRUzHU7iTynRBUGhQel0+S27oMkOrf8yucvEWwf6dq064IleQEjronyweUmLgcSIWrxZJcLohnruleJzSz1MngZ8lsccMNGQys1D1ycayYirMFqBneNnRPtpaqesy9aADvxyzCvp69DogeJEfe++FGGVaKijxRc//EwCqqSyaie+eH1+eVMva+QN3G3yjNgIiNo3ztc60hqQq0sG/K447zHuyr5xFc54fYFv2ZwQ== dave.nicponski@gmail.com davembp2"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC6P8roQA7hkbzFM8RqDY8DDkwfg+GbVzilBWjF6L8urodwkXtGPGIf/uyP18bC+ceYRyYbYRAeynVpueNPkcWQUf0GzvBXVkO6bHc7/M6Dj8VYe3v/lgeb6fyVRiI7khsS1ra37asPCOLxLqzYUh8+ml5tzmED3dwpgPcULw0/jnRaKlzJ/TNaDAI1u69FBbDswblNhFqSoQq1C6nUHb2hf9Zegb3FHwy4pE3LVvxqZiVj1z0zlrNVWHYM/LN4sihp9n81llHGDLa0ReZiYkgPBgvTn90XKbZ/gI3RuxYL52cxUohP2r+P4G2nIvaJK4SK9quEIXYhro7dJRz6h3SV dave.nicponski@gmail.com chromebook"
      ];
    };
  };

  virtualisation.podman = {
    enable = true;
    autoPrune.enable = true;
    autoPrune.dates = "*-*-* *:00/15:00";
    defaultNetwork.settings.dns_enabled = true;
    dockerSocket.enable = true;
  };

}
