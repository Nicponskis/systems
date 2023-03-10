# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, inputs, pkgs, lib, ... }:

let
  # TODO(Dave): Move these into an attrset perhaps, for name scoping
  acmePort = 28888;
  acmeTlsPort = acmePort + 1;
  nicponskiFamilyDomain = "nicponski.family";
  acmeChallengePrefix = "_acme-challenge";
  nicponskiChallengeDomain = "${acmeChallengePrefix}.${nicponskiFamilyDomain}";
  nicponskiDevDomain = "nicponski.dev";
  stitchpiDomain = "stitchpi.${nicponskiFamilyDomain}";
  foopiDomain = "foo.${stitchpiDomain}";
  streamDomain = "stream.${nicponskiFamilyDomain}";
  streamChallengeDomain = "${acmeChallengePrefix}.${streamDomain}";
in {
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  boot = {
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

    #kernelPackages = pkgs.linuxPackages_5_4; # Works
    kernelParams = ["cma=64M"];

    #kernelPackages = pkgs.linuxPackages_rpi3;
    kernelPackages = pkgs.linuxPackages_5_10; # Works
    #kernelPackages = pkgs.linuxPackages_5_15;
    #kernelParams = ["cma=128M"];
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
      l = "exa -la --color=always";
      ls = "exa -a --color=always";

      less = "less -R";
      LESS = "less -R --no-lessopen";
    };

    #shells = [];

    # List packages installed in system profile. To search, run:
    # $ nix search wget
    systemPackages = with pkgs; [
      awscli
      bash-completion
      bat
      colordiff
      coreutils
      crawl
      dig
      duf
      exa
      fd
      file
      fx
      fzf
      gdb
      git
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
      tmux
      tmuxPlugins.continuum
      tmuxPlugins.copycat
      tmuxPlugins.logging
      tmuxPlugins.pain-control
      tmuxPlugins.prefix-highlight
      tmuxPlugins.resurrect
      tmuxPlugins.sensible
      tmuxPlugins.yank
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
    ] ++ (
      let
        retroArchWith = cores: [ (pkgs.retroarch.override {cores = cores;}) ] ++ cores;
      in
        with pkgs.libretro; retroArchWith [
          mesen # NES
          bsnes-mercury-performance # SNES
          mupen64plus # N64
          picodrive # Sega Genesis
          beetle-psx-hw # Playstation
        ]
    );
  };

  fileSystems = let
        # this line prevents hanging on network split
        automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=600,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
      in {
    "/mnt/Media" = {
      device = "//192.168.4.1/Media";
      fsType = "cifs";
      options = ["${automount_opts},vers=2.0,credentials=/etc/nixos/secrets/smb/smb-secrets"];
    };
    "/mnt/Emulation" = {
      device = "192.168.4.1:/mnt/root/nfs/Emulation";
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
    firewall.allowedTCPPorts = [ 53 80 443 acmePort acmeTlsPort ];
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

  nixpkgs = {
    config = {
      allowUnfree = true;
    };

    overlays = [
      # Fix kernel wifi support by using an older firmware version, as per
      # the nixos RaspPI WLAN section
      (self: super: {
        linux-firmware-oldwifi = super.linux-firmware.overrideAttrs (old: {
          version = "2020-12-18";
          src = pkgs.fetchgit {
            url = "https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git";
            rev = "b79d2396bc630bfd9b4058459d3e82d7c3428599";
            sha256 = "1rb5b3fzxk5bi6kfqp76q1qszivi0v1kdz1cwj2llp5sd9ns03b5";
          };
          outputHash = "1p7vn2hfwca6w69jhw5zq70w44ji8mdnibm1z959aalax6ndy146";
        });
      })
    ];
  };


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

  security = {
    acme = {
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

    sudo = {
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
  };

  # List services that you want to enable:
  services = {
    bind = {
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

    ddclient = {
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
    #dhcpd4 = {
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

    fake-hwclock.enable = true;

    grafana = {
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
    gvfs = {
      enable = true;
      package = lib.mkForce pkgs.gnome3.gvfs;
    };

    nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      #recommendedProxySettings = true;
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
      # Below line and let binding are WIP
      } // (let
        wildcardDomains = [
          "wildcard.${nicponskiFamilyDomain}"
          "${config.services.grafana.domain}"
        ];
      in {
        "wildcard.${nicponskiFamilyDomain}" = {
          addSSL = true;

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

    prometheus = {
      enable = true;
      enableReload = true;
      exporters = {
        node = {
          enable = true;
          enabledCollectors = [
            # "systemd"
          ];
          port = 9002;
        };
        process = {
          enable = true;
          settings.process_names = [
            # Remove nix store path from process name
            {
              name = "{{.Matches.Wrapped}} {{ .Matches.Args }}";
              cmdline = [ "^/nix/store[^ ]*/(?P<Wrapped>[^ /]*) (?P<Args>.*)" ];
            }
          ];
        };
        systemd = {
          enable = true;
        };
      };
      extraFlags = [
        "--storage.tsdb.retention.size=256MB"
      ];
      globalConfig = {
        scrape_interval = "15s";
      };
      port = 9001;
      retentionTime = "30d";
      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [{
            targets = [
              # TODO(Dave): This should be done via a map over enabled exporters :/
              "127.0.0.1:${toString config.services.prometheus.exporters.node.port}"
              "127.0.0.1:${toString config.services.prometheus.exporters.process.port}"
              "127.0.0.1:${toString config.services.prometheus.exporters.systemd.port}"
            ];
          }];
        }
      ];
    };

    # Enable the OpenSSH daemon.
    openssh = {
      ports = [ 22 62832 ];
      enable = true;
    };

    # Enable CUPS to print documents.
    # printing.enable = true;

    x2goserver = {
      enable = true;
      superenicer.enable = true;
    };

    xserver = {
      autorun = true;
      # Enable the X11 windowing system.
      enable = true;
      exportConfiguration = true;
      resolutions = [
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
      #desktopManager.lxqt.enable = true;
      # https://wiki.x2go.org/doku.php/doc:de-compat
      #desktopManager.mate.enable = true;
      desktopManager.xterm.enable = true;

      displayManager.autoLogin = {
        enable = true;
        user = "dave";
      };
      #displayManager.sddm.enable = true;
      displayManager.lightdm.enable = true;

      windowManager."2bwm".enable = true;
    };
  };

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  # Use 2GB of additional swap memory
  swapDevices = [ { device = "/swapfile"; size = 2048; } ];

  system = {
    # This value determines the NixOS release with which your system is to be
    # compatible, in order to avoid breaking some software such as database
    # servers. You should change this only after NixOS release notes say you
    # should.
    stateVersion = "19.09"; # Did you read the comment?
  };

  systemd = {
    services = {
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

  # TODO(Dave): Replace this with mutable=false and a password hash!
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users = {
    mutableUsers = false;

    users."dave" = {
      createHome = true;
      extraGroups = [ "wheel" "audio" "video" "tty" "adm" "messagebus" ]; # Enable ‘sudo’ for the user.
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

    # users."root".openssh.authorizedKeys.keys = [
    #   # TODO(Dave): Should probably make the pibuilder only able to access particular
    #   # nix system-related commands like updating the system and boot profiles.
    #   # Can do this by using a new system-update-only user with some `sudo NOPASSWD`
    #   # config entries, one for each possible `targetHostCmd` invocation in the
    #   # `nixos-rebuild` script.
    #   # TODO(Dave): Remove this from `root`!!
    #   "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBGjtYCp9zMMsGp9d4bYtywB15Li8Pag9kFTU7XS/v3U/PZNprD9+RNp6X9k2RRg0GfIzsn15Kw59ka75gAEFi7E= pibuilder@auto.builder.arm.aws"
    # ];
  };
}

