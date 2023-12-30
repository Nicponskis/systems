# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, inputs, pkgs, lib, ... }:

let
  # TODO(Dave): Move these into an attrset perhaps, for name scoping
  acmePort = 28888;
  acmeTlsPort = acmePort + 1;
  grafanaPort = 14080;
  grafanaTlsPort = 14443;
  acmeChallengePrefix = "_acme-challenge";
  changedetection-io-port = 5221;
  foopiDomain = "foo.${stitchpiDomain}";
  nasAddress = "10.68.0.1";
  nicponskiChallengeDomain = "${acmeChallengePrefix}.${nicponskiFamilyDomain}";
  nicponskiDevDomain = "nicponski.dev";
  nicponskiFamilyDomain = "nicponski.family";
  stitchpiDomain = "stitchpi.${nicponskiFamilyDomain}";
  streamDomain = "stream.${nicponskiFamilyDomain}";
  streamChallengeDomain = "${acmeChallengePrefix}.${streamDomain}";

  portForwarded = port: (10000 + port);

  myRetroarch = (
      let
        retroArchWith = cores: [ (pkgs.retroarch.override {cores = cores;}) ] ++ cores;
      in
        with pkgs.libretro; retroArchWith [
          mesen # NES
          #bsnes # SNES
          #bsnes-mercury-performance # SNES
          snes9x # SNES
          # snes9x2010 # SNES  # Haven't needed to use this one yet, so removing it for now.
          mupen64plus # N64
          picodrive # Sega Genesis
          beetle-psx-hw # Playstation
        ]
    );
in {
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix

      # Local stuff.  Should be migrated to a shared location i guess.
      ./dwarffs.nix
      ./iptables_exporter.nix
    ];

  boot = {
    consoleLogLevel = 5;

    loader = {
      # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
      grub.enable = false;
      # Enables the generation of /boot/extlinux/extlinux.conf
      generic-extlinux-compatible.enable = true;

      raspberryPi.firmwareConfig = ''
        gpu_mem=128
        # trying lower amount per
        # https://docs.mesa3d.org/drivers/vc4.html#performance-tricks
        #gpu_mem=64
        dtparam=audio=on
      '';
    };

    # TODO: `rpi3` package's kernel modules seems to be missing
    # `achi` module for some reason, causing the build to fail.
    #initrd.includeDefaultModules = false;

    kernelParams = [
      #"cma=64M"  # Older, default value for rasp pi3
      "cma=128M"
    ];
    #kernelParams = ["cma=128M"];

    #kernelPackages = pkgs.linuxPackages_5_4; # Works
    #kernelPackages = pkgs.linuxPackages_rpi3;  # Doesn't work, apparently?
    kernelPackages = pkgs.linuxPackages_5_10; # Works
    #kernelPackages = pkgs.linuxPackages_5_15;
  };

  environment = {
    etc."machine-id".text = "b8eaf6f0bd4b411c97fd3e3b4187e2ee";

    extraOutputsToInstall = [
      "man"
      "dev"
    ];

    pathsToLink = [
      "/bin"
      "/etc"
      "/share"
      "/share/tmux-plugins"
    ];

    shellAliases = {
      l = "${pkgs.eza}/bin/eza -lag --color=always --color-scale";
      ls = "${pkgs.eza}/bin/eza -ag --color=always --color-scale";

      less = "less -R";
      LESS = "less -R --no-lessopen";
    };

    #shells = [];

    # List packages installed in system profile. To search, run:
    # $ nix search wget
    # TODO(Dave): The above no longer works!  Figure out the appropriate system-flake-relevant command.
    # TODO(Dave): Splitting these up into groups might be useful, and especially
    # for sharing subsets amongst various machines.  Will also make "adding or
    # removing related packages as an atomic unit" much easier (and saner) as
    # the list continues to grow.
    systemPackages = with pkgs; [
      awscli
      bash-completion
      bat
      colordiff
      coreutils
      crawl
      dig
      duf
      elfutils  # Includes eu-stack, eu-readelf, etc.  Added w/ gdb.
      eza
      fd
      file
      fx
      fzf
      gdb  # Can we get one without python support for better size perhaps?
      git
      # Maybe remove this eventually
      glxinfo # gives `glxgears` binary to test x11
      hexyl
      html2text
      htop
      inetutils
      libraspberrypi
      lshw
      lsof
      # non-xwindows authentication agent, used for browsing samba network shares
      lxqt.lxqt-policykit
      moreutils
      mosh
      ncdu
      nethack
      nmap
      nnn
      openssh
      peco
      pstree
      python3
      ripgrep-all
      silver-searcher
      tig
      # TODO(Dave): Remove this block
      # tmux
      # tmuxPlugins.continuum
      # tmuxPlugins.copycat
      # tmuxPlugins.logging
      # tmuxPlugins.pain-control
      # tmuxPlugins.prefix-highlight
      # tmuxPlugins.resurrect
      # tmuxPlugins.sensible
      # tmuxPlugins.yank
      tree
      vim
      vimPlugins.lightline-vim
      vimPlugins.syntastic
      #vimPlugins.unison-syntax
      #vimPlugins.vim-go
      vimPlugins.vim-nix
      vimPlugins.vim-scala
      vimPlugins.Vundle-vim
      watch
      wget
    ] ++
      myRetroarch
    ;
  };

  fileSystems = let
        # this line prevents hanging on network split
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=600,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
      in {
    "/mnt/Media" = {
      device = "//${nasAddress}/Media";
      fsType = "cifs";
      options = ["${automount_opts},vers=2.0,credentials=/etc/nixos/secrets/smb/smb-secrets"];
    };
    "/mnt/Emulation" = {
      device = "${nasAddress}:/mnt/root/nfs/Emulation";
      fsType = "nfs";
      options = ["${automount_opts},noatime,rw,sync"];
    };
  };

  fonts = {
    enableDefaultFonts = true;
    fontDir.enable = true;
    fonts = with pkgs; [
      dejavu_fonts
      hack-font
    ];
  };


  hardware = {
    # Better than `allowNonFree` ?
    enableRedistributableFirmware = true;

    opengl.enable = true;
  };

  networking = {
    hostName = "lidjamoypi"; # Define your hostname.

    wireless = {
      enable = true;  # Enables wireless support via wpa_supplicant.
      interfaces = [ "wlan0" ];
      driver = "brcmfmac,nl80211,wext";

      networks = {
        lidjamoyfast24 = {
          pskRaw = "a5b8c0622749e32fa383add8b7bd745098b5b7912eb0a2bdf48df1eeedf6eeff";
        };
        # Reenable if you need the open guest network
        #lidjamoyguest = { };
      };
    };

    # The global useDHCP flag is deprecated, therefore explicitly set to false here.
    # Per-interface useDHCP will be mandatory in the future, so this generated config
    # replicates the default behaviour.
    useDHCP = false;

    #nat = {
    #  enable = true;
    #  externalInterface = "wlan0";
    #  forwardPorts = [
    #    # { destination = "1.2.3.4"; proto = "tcp"; sourcePort = 12345;  }
    #  ];
    #  #internalIPs = [ "10.3.14.0/24" ];
    #  internalInterfaces = [ "eth0" ];
    #};

    interfaces = {
      eth0.useDHCP = true;
      #eth0.useDHCP = false;
      #eth0.ipv4.addresses = [ { address = "10.3.14.159"; prefixLength = 24; } ];

      wlan0.useDHCP = true;
      # Original
      wlan0.macAddress = "B8:27:EB:F1:A6:F7";
      # Cloned from ASUS
      #wlan0.macAddress = "9C:5C:8E:8B:10:CC";

      #bridge0 = {
      #  name = "bridge0";
      #  ipAddress = "10.3.14.159";
      #  prefixLength = 24;
      #  virtual = true;
      #};
    };
    #bridges = {
    #  bridge0 = {
    #    interfaces = ["wlan0" "eth0"];
    #    rstp = false;
    #  };
    #};

    # Configure network proxy if necessary
    # proxy.default = "http://user:password@proxy:port/";
    # proxy.noProxy = "127.0.0.1,localhost,internal.domain";


    # Open ports in the firewall.
    firewall.allowedTCPPorts = [
      53 80 443
      acmePort acmeTlsPort
      grafanaPort grafanaTlsPort
      # (portForwarded changedetection-io-port)
    ];
    # firewall.allowedUDPPorts = [ ... ];
    firewall.allowedUDPPortRanges = [
      { from = 53; to = 53; }
      { from = 31415; to = 32416; } # mosh (externally opened ports)
      { from = 60000; to = 61000; } # mosh
    ];
    # Or disable the firewall altogether.
    # firewall.enable = false;

    # Enable SAMBA share discovery (for network-shared drives)
    firewall.extraCommands = ''iptables -t raw -A OUTPUT -p udp -m udp --dport 137 -j CT --helper netbios-ns'';
  };


  nix = {
    #buildMachines = [{
    #  hostName = "nixbuilder";
    #  mandatoryFeatures = [ ];
    #  maxJobs = 2;
    #  speedFactor = 2;
    #  supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
    #  system = "aarch64-linux";
    #}];

    checkConfig = true;

    daemonCPUSchedPolicy = "idle";  # Or try "batch", default: "other"
    daemonIOSchedClass = "idle";  # Or try "best-effort" (the default)
    #daemonIOSchedPriority = 5; # (0:high to 7:low, only used for 'best-effort')

    #distributedBuilds = true;
    extraOptions = ''
      builders-use-substitutes = true
    '';


    #nixPath = lib.mkDefault (lib.mkBefore [ "nixpkgs=/nix/var/nix/profiles/per-user-root/channels/nixos-21.11" ]);

    settings = {
      auto-optimise-store = true;

      experimental-features = [ "nix-command" "flakes" ];
      # Force use of remote builder by default
      #max-jobs = 0;
      max-jobs = 4;

      trusted-users = [ "root" "dave" "pibuilder" ];
    };
  };

  nixpkgs.config = {
    allowUnfree = true;
  };

  nixpkgs.overlays = [
    # Fix kernel wifi support by using an older firmware version, as per
    # the nixos RaspPI WLAN section
    (final: prev: {
      linux-firmware-oldwifi = prev.linux-firmware.overrideAttrs (old: {
        version = "2020-12-18";
        src = pkgs.fetchgit {
          url = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git";
          rev = "b79d2396bc630bfd9b4058459d3e82d7c3428599";
          sha256 = "1rb5b3fzxk5bi6kfqp76q1qszivi0v1kdz1cwj2llp5sd9ns03b5";
        };
        outputHash = "1p7vn2hfwca6w69jhw5zq70w44ji8mdnibm1z959aalax6ndy146";
      });
    })

    # Patch changedetection-io to not phone home.
    (final: prev: {
      changedetection-io = prev.changedetection-io.overrideAttrs (ffinal: pprev: {
        patches = (pprev.patches or []) ++ [
          ./patches/0001-WIP-Elide-the-phone-home-stuff.patch
        ];
      });
    })
  ];


  # Select internationalisation properties.
  # i18n = {
  #   consoleFont = "Lat2-Terminus16";
  #   consoleKeyMap = "us";
  #   defaultLocale = "en_US.UTF-8";
  # };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = { enable = true; enableSSHSupport = true; };

  programs.gamemode.enable = true;
  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [
      better-mouse-mode
      continuum
      copycat
      fuzzback  # Maybe, if deps aren't too heavyweight
      logging
      pain-control
      prefix-highlight
      resurrect
      sensible
      yank

      tmux-thumbs
    ];
    terminal = "screen-256color";
  };

  security.acme = {
    acceptTerms = true;
    certs = {
      #"${foopiDomain}" = {
      #  credentialsFile = "/var/lib/secrets/certs.foopi.secret";
      #  # We don't need to wait for propagation since this is a local DNS server
      #  dnsPropagationCheck = false;
      #  dnsProvider = "rfc2136";
      #  domain = "*.${foopiDomain}";
      #};
      "${streamDomain}" = {
        # TODO(Dave): Replace the credentials file with something using agenix!!
        credentialsFile = "/var/lib/secrets/certs.nicponski.secret";
        # We don't need to wait for propagation since this is a local DNS server
        dnsPropagationCheck = false;
        dnsProvider = "rfc2136";

        # domain = "*.${nicponskiFamilyDomain}";
        extraDomainNames = [
          "*.${streamDomain}"
          # TODO(Dave): Grab a top-level wildcard here as well perhaps, instead
          # of 'stream.nicponski.family' default from name??
        ];
      };

      "${nicponskiFamilyDomain}" = {
        # TODO(Dave): Replace the credentials file with something using agenix!!
        credentialsFile = "/var/lib/secrets/certs.nicponski.secret";
        # We don't need to wait for propagation since this is a local DNS server
        dnsPropagationCheck = false;
        dnsProvider = "rfc2136";
        domain = "*.${nicponskiFamilyDomain}";
      };
    };
    defaults = {
      email = "dave.nicponski+acme.certs@gmail.com";
      # `nginx` needs to be able to access these certs!
      group = config.users.users.nginx.group;
    };
  };

  security.sudo = {
    extraRules = [
      {
        users = ["${config.users.users."pibuilder".name}"];
        commands = let
          full = re: "^${re}$";
          sw = bin: "/run/current-system/sw/bin/${bin}";
          profileRE = "/nix/var/nix/profiles/system(-profiles/[^/]+)?";
          systemRE = "/nix/store/[a-zA-Z0-9]{32}-nixos-system-${config.system.name}-[^/]+";
          switchRE = "${systemRE}/bin/switch-to-configuration";
          actionRE = "switch|boot|test|dry-activate";
          nopass = command: {
            inherit command;
            options = [ "NOPASSWD" "LOG_INPUT" "LOG_OUTPUT" ];
          };
          in [
            (nopass "${sw "nix-env"} ${full "-p ${profileRE} --set ${systemRE}"}")
            (nopass "${sw "nix-env"} ${full "--rollback -p ${profileRE}"}")
            (nopass "${sw "nix-env"} ${full "-p ${profileRE} --list-generations"}")
            (nopass "${full switchRE} ${full actionRE}")
          ];
      }
    ];
  };

  # List services that you want to enable:
  services.bind = {
    enable = true;
    extraConfig = ''
      include "/var/lib/secrets/dnskeys.conf";
    '';
    zones = [
      rec {
        name = foopiDomain;
        file = "/var/db/bind/${name}";
        master = true;
        extraConfig = "allow-update { key rfc2136key.${foopiDomain}; };";
      }

      rec {
        name = "${nicponskiChallengeDomain}";
        file = "/var/db/bind/${name}";
        master = true;
        extraConfig = "allow-update { key rfc2136key.${nicponskiChallengeDomain}; };";
      }

      rec {
        name = "${streamChallengeDomain}";
        file = "/var/db/bind/${name}";
        master = true;
        extraConfig = "allow-update { key rfc2136key.${nicponskiChallengeDomain}; };";
      }
    ];
  };

  # Watch webpages for changes
  services.changedetection-io = {
    # enable = true;

    baseURL = "https://sitechanges.dave.nicponski.dev:${toString (portForwarded changedetection-io-port)}/";
    behindProxy = false;
    # chromePort = 4444;  # defaults to 4444
    # datastorePath = "/var/lib/changedetection-io";
    environmentFile = pkgs.writeText "chagedetection-io_environment" ''
      HIDE_REFERER=true
    '';
    # listenAddress = "0.0.0.0";  # Expose externally as well.  Defaults to `localhost`.
    port = changedetection-io-port;  # Defaults to port 5000
    webDriverSupport = true;  # Enable to use headless Chromium for rendering
  };
  # Tacky fix for using the docker image on ARM
  virtualisation.oci-containers.containers =
    lib.mkIf config.services.changedetection-io.webDriverSupport {
      changedetection-io-webdriver.image = lib.mkForce "seleniarm/standalone-chromium";
    };


  services.ddclient = {
    enable = true;

    domains = [ "lidjamoypi.${nicponskiFamilyDomain}" ];
    interval = "1min";
    # TODO(Dave): Replace w/ agenix secret
    passwordFile = "/etc/nixos/secrets/ddclient/password";
    protocol = "googledomains";
    username = "HIPNWcxNQomCcWS4";
    verbose = true;
  };
  # This block would act as a DHCP server for ETH0, assigning IP addresses
  # to connected devices.
  #services.dhcpd4 = {
  #  enable = true;
  #  interfaces = ["eth0"];
  #  extraConfig = ''
  #    subnet 10.3.14.0 netmask 255.255.255.0 {
  #      range 10.3.14.160 10.3.14.240;
  #      authoritative;
  #      max-lease-time      604800;
  #      default-lease-time  86400;
  #
  #      option subnet-mask          255.255.255.0;
  #      option broadcast-address    10.3.14.255;
  #      option routers              10.3.14.159;
  #      option domain-name-servers  8.8.8.8;
  #    }
  #  '';
  #};

  services.dwarffs = {
    enable = true;
    gcDelay = "3d";
  };

  services.fake-hwclock.enable = true;

  services.grafana = {
    enable = true;
    # Get EIC (KiB, MiB, etc) units axis bugfix!
    package = inputs.latest.legacyPackages.${pkgs.system}.grafana;
    settings.server = {
      domain = "lidjamoypi";
      http_addr = "127.0.0.1";
      port = 3000;
    };
    #protocol = "http";
  };

    # For browsing samba shares (in xwindows)
  services.gvfs = {
    enable = true;
    package = lib.mkForce pkgs.gnome3.gvfs;
  };

  services.iptables_exporter = {
    enable = true;
    port = 9102;
  };

  # TODO(Dave): This is cool but the rpi is underpowered for it
  # services.jellyfin.enable = true;
  # #services.jellyfin.openFirewall = true;
  # networking.firewall.allowedUDPPorts = [ 1900 7359 ];

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts = {
      # TODO(Dave): Is this even used now?  :thinking_face:
      "${stitchpiDomain}.acme" = {
        addSSL = true;
        enableACME = true;
        listen = [ {
          addr = "0.0.0.0";
          port = acmePort;
        } {
          addr = "0.0.0.0";
          port = acmeTlsPort;
          ssl = true;
        }];
        locations."/" = {
          return = "301 https://google.com";
        #  #extraConfig = ''
        #  #  add_header 'Access-Control-Allow-Origin' "*" always;
        #  #'';
        #  proxyPass = "http://127.0.0.1:11470";  # Stremio
        #  proxyWebsockets = true;
        };
        serverName = stitchpiDomain;
      };

      "${stitchpiDomain}" = {
        addSSL = true;
        locations."/" = {
          #extraConfig = ''
          #  add_header 'Access-Control-Allow-Origin' "*" always;
          #'';
          proxyPass = "http://127.0.0.1:11470";  # Stremio
          proxyWebsockets = true;
        };
        # TODO(Dave): Remove the original perhaps?
        useACMEHost = nicponskiFamilyDomain; #stitchpiDomain;
      };

      # # Needed because `.dev` TLD auto-pins certs via HSTS.  Grrrr.
      # "sitechanges.dave.nicponski.dev" = {
      #   enableACME = true;
      #   forceSSL = true;
      #   listen = [{
      #     addr = "0.0.0.0";
      #     port = portForwarded changedetection-io-port;
      #     ssl = true;
      #   }];
      #   locations."/" = {
      #     proxyPass = "http://localhost:${toString changedetection-io-port}";
      #     proxyWebsockets = true;
      #   };
      # };

    # Below line and let binding are WIP
    } // (let
      wildcardDomains = [
        "wildcard.${nicponskiFamilyDomain}"
        "${config.services.grafana.domain}"
      ];
    in {
      "grafana.${nicponskiFamilyDomain}" = {
        addSSL = true;

        # TODO(Dave): This is copied from the acme stanza.
        listen = [ {
          addr = "0.0.0.0";
          port = grafanaPort;
        } {
          addr = "0.0.0.0";
          port = grafanaTlsPort;
          ssl = true;
        }];

        locations."/" = {
          extraConfig = ''
            proxy_set_header Host $host;
          '';
          proxyPass = "http://127.0.0.1:${toString config.services.grafana.port}";
          proxyWebsockets = true;
        };
        # TODO(Dave): Stop using these, do something
        # more intentional :)
        serverAliases = wildcardDomains;
        useACMEHost = nicponskiFamilyDomain;
      };

      "localhost" = {
        # addSSL = true;
        default = true;
        locations."/" = {
          return = "200 'Maybe try one of: \"${
            lib.concatStringsSep " " (
              # TODO(Dave): Iterate over all virtualHost domains + serverAliases
              wildcardDomains
              )
          }\"'";
        };
        # useACMEHost = nicponskiFamilyDomain;
      };

    }) // (let
      # TODO(Dave): This should be template-able with a matcher in the return rule
      streamer = digit: {
        "${digit}.${streamDomain}" = {
          forceSSL = true;
          listen = let
            port = p: {
              addr = "0.0.0.0";
              port = p;
            };
          in [
            # (port 80)
            # TODO(Dave): This kinda sucks :(
            (port acmePort)
            ((port acmeTlsPort) // { ssl = true; })
          ];
          locations."/" = {
            return = "301 https://10-69-0-${digit}.519b6502d940.stremio.rocks:12470";
          };
          useACMEHost = "${streamDomain}";
        };
      };
    in (streamer "1") // (streamer "2")
    );
  };

  services.prometheus = {
    enable = true;
    enableReload = true;
    exporters = {
      node = {
        enable = true;
        enabledCollectors = [ ];
        port = 9002;
      };
      process = {
        enable = true;
        extraFlags = ["--debug"];
        settings.process_names = [
          # Remove nix store path from process name
          {
            name = "{{.Matches.Wrapped}} {{ .Matches.Args }}";
            cmdline = [ "^/nix/store[^ ]*/(?P<Wrapped>[^ /]*) (?P<Args>.*)" ];
          }
        ];
      };
    };
    extraFlags = [
      "--storage.tsdb.retention.size=1GB"
      #"--web.enable-admin-api"  # TODO(dave): Remove this after deleting the series
    ];
    globalConfig = {
      scrape_interval = "15s";
    };
    port = 9001;
    retentionTime = "90d";

    # TODO(Dave): Currently these are grouped by source.  Perhaps grouping
    # by "logical metric type" would make more sense, as this could allow
    # shared configuration for things like label replacement in contexts
    # where is makes sense to share these (timeseries sets of the same metrics
    # from multiple sources, for instance all "iptables"/"ip6tables"
    # metrics) and use common relabeling or rewriting rules on them alone.
    scrapeConfigs = let
      mkTargets = host: lib.mapAttrsToList (_: v: "${host}:${toString v}");
      relabels = {
        iptables.version = [{
          source_labels = ["__name__"];
          regex = "iptables_.*";
          target_label = "ip_stack";
          replacement = "IPv4";
        } {
          source_labels = ["__name__"];
          regex = "ip6tables_.*";
          target_label = "ip_stack";
          replacement = "IPv6";
        }];
        iptables.version_merge = [{
          source_labels = ["__name__"];
          regex = "ip(?:|6)tables_(.*)";
          target_label = "__name__";
          replacement = "merged_iptables_$1";
        }];
      };
    in [{
      job_name = "local-node";
      metric_relabel_configs = [] ++
        relabels.iptables.version ++
        relabels.iptables.version_merge;
      static_configs = [{
        targets = let
          s = config.services;
          pe = s.prometheus.exporters;
        in mkTargets "127.0.0.1" {
          node = pe.node.port;
          process = pe.process.port;
          iptables = s.iptables_exporter.port;
          prometheus = s.prometheus.port;
        };
        labels.source = "lidjamoypi";
      }];
    } {
      job_name = "router";
      metric_relabel_configs = [] ++
        relabels.iptables.version ++
        relabels.iptables.version_merge;
      static_configs = [{
        targets = mkTargets "10.68.0.1" {
          # Would really love a way to magically discover these!
          node = 9100;
          process = 9101;
          iptables = 9102;
        };
        labels.source = "rt-ax88u";
      }];
    }];
  };

    # Enable the OpenSSH daemon.
  services.openssh = {
    ports = [ 22 62832 ];
    enable = true;
  };

    # Enable CUPS to print documents.
    # services.printing.enable = true;

  services.x2goserver = {
    enable = true;
    superenicer.enable = true;
  };

  services.xserver = {
    autorun = true;
    # Enable the X11 windowing system.
    enable = true;
    exportConfiguration = true;
    inputClassSections = [
      # TODO(Dave): Move this into an X11-specific location perhaps?
      (builtins.readFile ./joystick-input.conf)
    ];
    modules = with pkgs.xorg; [
      xf86inputjoystick
    ];
    resolutions = [
      # 16:9 resolutions
      { x = 1280; y = 720; }  # Best for emulator performance :(
      { x = 1920; y = 1080; }  # HDMI tv preferred resolution

      # 4:3 resolutions
      { x = 1024; y = 768; }
      { x = 800; y = 600; }
      { x = 1600; y = 1200; }
      { x = 640; y = 480; }
    ];

    layout = "us";
    videoDrivers = [ /*"fbdev"*/ "modesetting" "fbdev" ];

    # xkbOptions = "eurosign:e";

    # Enable touchpad support.
    # libinput.enable = true;

    # Enable the KDE Desktop Environment.
    # displayManager.sddm.enable = true;
    # desktopManager.plasma5.enable = true;
    #desktopManager.xfce.enable = true;

    # Incompatible with x2go server :'(
    desktopManager.lxqt.enable = true;

    # https://wiki.x2go.org/doku.php/doc:de-compat
    # desktopManager.mate.enable = true;
    # desktopManager.retroarch.enable = true;
    # desktopManager.retroarch.package = (builtins.head myRetroarch);
    # desktopManager.xterm.enable = true;

    displayManager.autoLogin = {
      enable = true;
      user = "dave";
    };
    #displayManager.sddm.enable = true;
    displayManager.lightdm.enable = true;

    # Disable the annoying "screen blanking" / kill HDMI signal that was
    # happening in the middle of my games, every 10 minutes.
    serverFlagsSection = ''
      Option "BlankTime" "0"
      # TODO(Dave): Are the below useful?
      Option "StandbyTime" "0"
      Option "SuspendTime" "0"
      Option "OffTime" "0"
    '';

    # TODO(dave): Maybe get rid of this if it doesn't help?
    updateDbusEnvironment = true;

    windowManager."2bwm".enable = true;
  };
  services.fractalart = {  # Goes w/ xserver, hence not alphabetized
    enable = true;
    width = 1280;
    height = 720;
  };
  # TODO(Dave): Find a way to combine this with the `services.` part. :(
  # Disable the screensaver.
  environment.lxqt.excludePackages = [ pkgs.xscreensaver ];

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  # Use 5GB of additional swap memory
  swapDevices = [ { device = "/swapfile"; size = 1024 * 5 /*MiB*/; randomEncryption.enable = true; } ];

  system = {
    # This value determines the NixOS release with which your system is to be
    # compatible, in order to avoid breaking some software such as database
    # servers. You should change this only after NixOS release notes say you
    # should.
    stateVersion = "19.09"; # Did you read the comment?
  };

  systemd = {
    services = {
      # TODO(Dave): This always seems to fail and doesn't actually seem necessary!?!  REMOVE IT IF SO!
      # Enable bluetooth support, as per the nixos RaspPI Bluetooth section
      btattach = {
        before = [ "bluetooth.service" ];
        after = [ "dev-ttyAMA0.device" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.bluez}/bin/btattach -B /dev/ttyAMA0 -P bcm -S 3000000";
        };
      };
    };
  };

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users = {
    mutableUsers = false;

    users."dave" = {
      createHome = true;
      extraGroups = [ "wheel" "audio" "video" "tty" "adm" "messagebus" "input" "render" ]; # Enable ‘sudo’ for the user.
      hashedPassword = "$y$j9T$4R36MYOFnwVVLvb6hHml1.$qacBsg3r9.hU/uy0WNOjxgL7KfZu7B016gSRvtzUNL9";
      home = "/home/dave";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCi+GbiMk0UqGYfG+7jmTGaKRtIVTFBwVG0p6kg3l4rsG2S7LCBG9MAgMQQKCfBay1SdXVZvr8wrc7TMj2dk0ZrnQklBd7Cn6hXE3rOiIa+1FFAtXfI4r6gMhzIa91uF63okW09wPYCUxUYmhNSGwC1rTytU5SE1jf5o/Asp/ZfHvmxhm5EUxw5qacS/Ilf4OhEWyQaQG6xeHnO4NCGThIpdTxC2Q9LpQAPlz6lZedEWTTLcXRTcG+olhxfudQ/JMdzQhqluVRCOgolIS32rvKi9st7H3D6q2sZH8MNnbl22FQNHg8f4fl34L1X/n/Zf6573eL0V5uKEtdachwrN+X5FUgwwzn7ivHjAxOHVHuWuADk+HVCG95zN1eyPLbCR8FwF/LtfjfQiF6Erwd3mNdjMK9J1upAfZkix7Ap8UDi2qmK5fzWNXcvFV7bFSo8kRd7ztMRUzHU7iTynRBUGhQel0+S27oMkOrf8yucvEWwf6dq064IleQEjronyweUmLgcSIWrxZJcLohnruleJzSz1MngZ8lsccMNGQys1D1ycayYirMFqBneNnRPtpaqesy9aADvxyzCvp69DogeJEfe++FGGVaKijxRc//EwCqqSyaie+eH1+eVMva+QN3G3yjNgIiNo3ztc60hqQq0sG/K447zHuyr5xFc54fYFv2ZwQ== dave.nicponski@gmail.com"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC6P8roQA7hkbzFM8RqDY8DDkwfg+GbVzilBWjF6L8urodwkXtGPGIf/uyP18bC+ceYRyYbYRAeynVpueNPkcWQUf0GzvBXVkO6bHc7/M6Dj8VYe3v/lgeb6fyVRiI7khsS1ra37asPCOLxLqzYUh8+ml5tzmED3dwpgPcULw0/jnRaKlzJ/TNaDAI1u69FBbDswblNhFqSoQq1C6nUHb2hf9Zegb3FHwy4pE3LVvxqZiVj1z0zlrNVWHYM/LN4sihp9n81llHGDLa0ReZiYkgPBgvTn90XKbZ/gI3RuxYL52cxUohP2r+P4G2nIvaJK4SK9quEIXYhro7dJRz6h3SV dave.nicponski@gmail.com chromebook"
      ];
    };

    groups.pibuilder = {};
    users."pibuilder" = {
      createHome = false;
      group = "pibuilder";
      home = "/var/empty";
      isSystemUser = true;
      openssh.authorizedKeys.keys = [
        # TODO(Dave): Should probably make the pibuilder only able to access particular
        # nix system-related commands like updating the system and boot profiles.
        # Can do this by using a new system-update-only user with some `sudo NOPASSWD`
        # config entries, one for each possible `targetHostCmd` invocation in the
        # `nixos-rebuild` script.
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBGjtYCp9zMMsGp9d4bYtywB15Li8Pag9kFTU7XS/v3U/PZNprD9+RNp6X9k2RRg0GfIzsn15Kw59ka75gAEFi7E= pibuilder@auto.builder.arm.aws"
      ];
      useDefaultShell = true;
    };
  };
}

