{ modulesPath, config, pkgs, lib, ... }:
let
  agenixCLI = pkgs.age;

  # aws_public_ip = let
  #   script = pkgs.callPackage ./aws_public_ip.nix { inherit secrets; };
  # in "${script}/bin/aws_public_ip";

  changedetection-io-port = 5221;

  maybeFileIfNonempty = filename:
    lib.optional (
      (builtins.pathExists filename) &&
      (builtins.stringLength (builtins.readFile filename) != 0)
      ) filename;

  secrets = with lib; (flip genAttrs) (n: {
    plain = config.age.secrets.${n}.path;
    cipher = ./secrets/${n}.age;
  }) [
    "awscli-ip_builder-pw"
    "awscli-s3fs-pw"
    "ddclient-pw"

    "test-secret"
  ];

  vims = (import ./nix/vims.nix) { inherit pkgs lib; };
  nix-portables = (import ./nix/nix-portable.nix) { inherit pkgs lib; };

  portForwarded = port: (10000 + port);
in {
  imports = [
    "${modulesPath}/virtualisation/amazon-image.nix"
    # ./nix/dwarffs.nix
  ];

  age.secrets = with lib; recursiveUpdate (mapAttrs (n: v: {file = v.cipher;}) secrets) {
    # Per-secret overrides go here
    awscli-ip_builder-pw.owner = "awscli";
    awscli-s3fs-pw.owner = "awscli";
  };
  #age.secrets = {
  #  "ddclient-pw".file = ./secrets/ddclient-pw.age;
  #};

  boot.tmpOnTmpfs = true;

  ec2.hvm = true;
  ec2.efi = true;

  environment.systemPackages = with pkgs; [
    # Essentials
    agenixCLI
    awscli
    gitMinimal  # TODO(Dave): Eliminate python here also
    mosh
    # nix-portables.bootstrap
    nix-portable
    s3backer
  ] ++ [
    # Really want
    compsize  # btrfs compression stats
    file
    htop
    nix-tree # Help with space analysis
    vims.minimalNormal
  ] ++ [
    # Nice to have...
    #gdb  # TODO(Dave): Reenable sans python
  ];

  fileSystems."/" = lib.mkForce {
    device = "/dev/disk/by-label/nixos-btrfs";
    fsType = "btrfs";
    options = [
      "compress=zstd:3" "subvol=root"
      "nossd"
    ];
  };

  # fileSystems."${config.services.dwarffs.cache}" = lib.mkIf config.services.dwarffs.enable {
  #   device = "/mnt/.s3backer/file";
  #   fsType = "btrfs";
  #   options = [
  #     "_netdev" "loop" "rw" "noatime" "nodiratime"
  #     "compress=zstd:6" "subvol=dwarffs-cache"
  #     "nossd"
  #     # TODO(Dave): Is this useful?  (Edit: Nope; prevents tmpfiles.d auto-cleanup!)
  #     #"x-systemd.automount" "x-systemd.idle-timeout=3h"
  #     "nofail"  # Failing to mount is not a system inhibiting failure
  #     "x-systemd.requires-mounts-for=/mnt/.s3backer/"
  #   ];
  # };

  fileSystems."/nix" = {
    device = "/dev/disk/by-label/nixos-btrfs";
    fsType = "btrfs";
    options = [
      "noatime"
      "compress=zstd:6" "subvol=nix"
      "nossd"
    ];
  };

  fileSystems."/mnt/.s3backer" = let
    s3Bucket = "vd-aarch64-nixos-builder-s3fs-001";
  in {
    device = "${pkgs.s3backer}/bin/s3backer#${s3Bucket}/s3backer/blocks";
    fsType = "fuse";
    noCheck = true;
    options = [
      "_netdev"
      "nofail"  # Failing to mount is not a system inhibiting failure
      "rw" "noatime" #"nodiratime"
      "listBlocks"
      # Block cache for performance?
      "blockCacheFile=/var/cache/s3backer/s3dev-blockcache"
        "blockCacheSize=125"  # Crank this once done with heavy local disk use
      "encrypt" "sse=AES256"
      "accessFile=${secrets.awscli-s3fs-pw.plain}"
      "blockHashPrefix"
      "blockSize=2M"  # TODO(Dave): Might have been better to increase this
      "force"  # Force mounting regardless of already-mounted flag.
      "region=us-east-1"
      #"reset-mounted-flag"
      "size=1T"
      "storageClass=INTELLIGENT_TIERING"
    ];
  };

  fileSystems."/mnt/s3fs" = {
    device = "/mnt/.s3backer/file";
    fsType = "btrfs";
    options = [
      "_netdev" "loop" "rw" "noatime" "nodiratime"
      "compress=zstd:6" "subvol=root"
      "nossd"
      "nofail"  # Failing to mount is not a system inhibiting failure
      "x-systemd.requires-mounts-for=/mnt/.s3backer/"
    ];
  };

  # These are huge!  Do we actually NEED them?  The non-flake system config seems
  # like it didn't include these at all!
  hardware.enableRedistributableFirmware = false;

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [
    (portForwarded changedetection-io-port)
  ];
  networking.firewall.allowedUDPPortRanges = [
    { from = 60000; to = 61000; } # mosh
  ];
  networking.hostName = "arm-builder-west";

  nix.gc = {
    automatic = true;
    dates = "daily";
    persistent = true;
    randomizedDelaySec = "3600sec";
  };

  # Shrink this system closure!!  It appears that all inputs
  # to the flake will be included by default.
  # TODO(Dave): Maybe include just the nixpkgs one?
  nix.registry = lib.mkForce { };

  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.settings.trusted-users = ["@wheel" "pibuilder"];

  nixpkgs.overlays = [
    # Upgrade `s3backer` to latest release
    (final: prev: {
      s3backer = prev.s3backer.overrideAttrs (old: rec {
        version = "2.0.2";
        src = old.src.overrideAttrs (oldSrc: {
          rev = version;
          sha256 = "sha256-xmOtL4v3UxdjrL09sSfXyF5FoMrNerSqG9nvEuwMvNM=";
        });
        autoreconfPhase = null;
      });
    })

    # `grub2` efiSupport (prevents near-duplicate grub packages being in
    # the system closure)
    # TODO(Dave): Migrate this into `grub/default.nix` and upstream it, ideally.
    (final: prev: {
      # TODO(Dave): Should set this to `config.ec2.efi` somehow
      grub2 = prev.grub2.override { efiSupport = true; };
    })

    # Shrink git completely!  Everything seems to use it, so replace the bloated one
    # with a minimal install...
    # TODO(Dave): Why doesn't this work?  :(
    # (final: prev: rec {
    #   #gitBase = prev.git;
    #   git = final.gitMinimal;
    # })

    # Patch changedetection-io to not phone home.
    (final: prev: {
      changedetection-io = prev.changedetection-io.overrideAttrs (ffinal: pprev: {
        patches = (pprev.patches or []) ++ [
          ./patches/0001-WIP-Elide-the-phone-home-stuff.patch
        ];
      });
    })

    (final: prev: {
      nix = prev.nix.overrideAttrs (ffinal: pprev: {
        patches = (pprev.patches or []) ++ [
          ./patches/0001-Stop-hard-linking-non-directory-inputs-as-this-will-.patch
        ];
      });
    })
  ];

  security.acme = {
    acceptTerms = true;
    certs = { };
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

            (nopass "${sw "htop"}")  # may as well :)
          ];
      }
    ];
  };

  # Watch webpages for changes
  services.changedetection-io = {
    enable = true;

    baseURL = "https://sitechanges.dave.nicponski.dev:${toString (portForwarded changedetection-io-port)}/";
    behindProxy = false;
    # chromePort = 4444;  # defaults to 4444
    datastorePath = "/mnt/s3fs/changedetection-io/data";
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

    domains = [ "west.builder.arm.aws.nicponski.dev" ];

    interval = "30sec";
    passwordFile = secrets.ddclient-pw.plain;
    protocol = "googledomains";
    username = "tsDqVBmzF2UmhpUb";
  };

  # TODO(Dave): This looks like vestigial leftovers from the rPI config.  Remove it?
  # services.dwarffs = {
  #   enable = true;
  #   gcDelay = "4h";
  # };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts = {
      # Needed because `.dev` TLD auto-pins certs via HSTS.  Grrrr.
      "sitechanges.dave.nicponski.dev" = {
        enableACME = true;
        forceSSL = true;
        listen = [{
          addr = "0.0.0.0";
          port = portForwarded changedetection-io-port;
          ssl = true;
        }];
        locations."/" = {
          proxyPass = "http://localhost:${toString changedetection-io-port}";
          proxyWebsockets = true;
        };
      };
    };
  };

  services.openssh = {
    extraConfig = ''
      AcceptEnv LANG LC_* NIX_STORE_DIR NIX_STATE_DIR
    '';
    passwordAuthentication = false;
  };

  system.stateVersion = "22.11"; # don't change unless nixos release notes say to do so!!

  systemd.services = {
    # # TODO(Dave): Move this to a module!  (and get it to work again on shutdown rather than reboot!!)
    # "release-public-ip" = {
    #   description = "Release any public IP address";
    #   after = ["network-online.target" "nix-daemon.service"];
    #   #environment.NIX_PATH = "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos";
    #   #path = with pkgs; [ awscli bashInteractive curl ];
    #   requires = ["network-online.target"];
    #   restartIfChanged = false;
    #   startLimitBurst = 3;
    #   startLimitIntervalSec = 60;
    #   #wantedBy = ["multi-user.target"];
    #   wantedBy = ["halt.target" "poweroff.target" "shutdown.target"];
    #   wants = [ "nix-daemon.service"];

    #   serviceConfig = {
    #     #ExecStart = "/run/current-system/sw/bin/echo Nothing to do at startup";
    #     ExecStart = "${aws_public_ip} drop";
    #     #ExecStop = "${aws_public_ip} drop";
    #     Group = "awscli";
    #     RemainAfterExit = true;
    #     #StandardError = "journal+console";
    #     StandardError = "journal";
    #     StandardOutput = "journal";
    #     Type = "oneshot";
    #     User = "awscli";
    #   };
    # };
  };

  systemd.tmpfiles.rules = [
    "d /var/cache/s3backer 0700 root root"
    "d /mnt/s3fs/changedetection-io/data 0700 changedetection-io changedetection-io"
  ];

  users = {
    mutableUsers = false;

    groups."awscli".members = ["awscli"];
    users."awscli" = {
      group = "awscli";
      isSystemUser = true;
    };
    users."console" = {
      extraGroups = ["wheel"];
      isNormalUser = true;
      hashedPassword = "$y$j9T$j6MLISztfwKPVd8HYbEuy.$jM0dh0rfP4q0tHcf5u2BBNxYW31JHL1rvn47f5HpLM1";
    };

    users."pibuilder" = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCqsa5ccTCbVGKxZdupKYkkNKch6MPaahPSfVYJa0fa9Eoj44T0Cz5pcnOorjHekKOTGJDU817vYZ2b9a7TsXuEGmJNOMzubn7jpydOoUkq826Hpa8RJUCkygxL7j2EZsm0h8FXKgB7Xbz39x9POG7Zrs5M3kCHVSr8MMSXEvjNIV81e1AR4lDOM3mlb0qpMB0AXkt0vEO+aEHBc4BkS4ff5i63AdN5TcEr/sQW1WpPdnnkmmnToHRtDI1AA/cDP6pOzw8ONcK1/J9W1vkWz7zW/kSFkeu91zoSBImRNelwZM6gJ580XzgWdeqDK5Q6u1x4lrlwtgWlDqOpZ2syphhwTuJIHGgr3YBYHr7nzCJ43RS0qG8M8wsS3n0BrRy+fTCatVYgJGKxnfNuzynTp3NYJjjVgZonTKDDzdlFakf6GEfekwJLX2wkTlSonBuWyzjVxn249HUBwKFz8hFyymbUWNWPu8Fv7hRtJrKWvrHOnIR0SVZoArO/mug9LeYZSrM= dave@lidjamoypi"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC3byObhoiui0p3ot+Dh/d5W1olb6g0oLYoQlqts1fjgxTsdJSqmjnlpkAC0SohZjERXRSIndwHeHkoFI875P9t3gJSbkRXTJ78WsiGmqYVYcJ87/aS6RIDRx8/2aHIorJMxYCv0WtytbDBXhPFosITT4jUhSRObFfAo5DfWnfnaiVO+AERP67XHT+mDQm/rz2lNIeqambkXQRcs0itFeuvoPTCuV6pGtzEoZRxFzPKubZHMVqoH2GJyXL5yGjO0Z2drKFYg6ZnQ3mTEecd+MLIaRpdEb2uAczdl9pR+d4BltCT9jS+N3OLrB3TM0tdxAdqk+vK06/aYiczZzKyMqlAAa04Vj9sdD5lUYm9az69z9FYnCZ84L4jPKUdpteLV7lwzbC/RTDW7a8aXeitrL6fwGbLTYeaHgK79WN6T4dlxKi7cnjRviLmpBSask/CxoDGvnIinuZIVWbSndl4MHQbfM63btNo32TIRdYB52n/tgss3p5euH8z3NQ51k/GZjE= root@lidjamoypi"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCi+GbiMk0UqGYfG+7jmTGaKRtIVTFBwVG0p6kg3l4rsG2S7LCBG9MAgMQQKCfBay1SdXVZvr8wrc7TMj2dk0ZrnQklBd7Cn6hXE3rOiIa+1FFAtXfI4r6gMhzIa91uF63okW09wPYCUxUYmhNSGwC1rTytU5SE1jf5o/Asp/ZfHvmxhm5EUxw5qacS/Ilf4OhEWyQaQG6xeHnO4NCGThIpdTxC2Q9LpQAPlz6lZedEWTTLcXRTcG+olhxfudQ/JMdzQhqluVRCOgolIS32rvKi9st7H3D6q2sZH8MNnbl22FQNHg8f4fl34L1X/n/Zf6573eL0V5uKEtdachwrN+X5FUgwwzn7ivHjAxOHVHuWuADk+HVCG95zN1eyPLbCR8FwF/LtfjfQiF6Erwd3mNdjMK9J1upAfZkix7Ap8UDi2qmK5fzWNXcvFV7bFSo8kRd7ztMRUzHU7iTynRBUGhQel0+S27oMkOrf8yucvEWwf6dq064IleQEjronyweUmLgcSIWrxZJcLohnruleJzSz1MngZ8lsccMNGQys1D1ycayYirMFqBneNnRPtpaqesy9aADvxyzCvp69DogeJEfe++FGGVaKijxRc//EwCqqSyaie+eH1+eVMva+QN3G3yjNgIiNo3ztc60hqQq0sG/K447zHuyr5xFc54fYFv2ZwQ== dave.nicponski@gmail.com davembp2"

        # Allow self-ssh from inside the bwrap chroot.
        # TODO(Dave): Can't we refer to the public key without having to embed it here?
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBGjtYCp9zMMsGp9d4bYtywB15Li8Pag9kFTU7XS/v3U/PZNprD9+RNp6X9k2RRg0GfIzsn15Kw59ka75gAEFi7E= pibuilder@auto.builder.arm.aws"
      ];
    };

    # TODO(Dave): Not sure if this works (do we use root inside the chroot jail even?)
    users."root".openssh.authorizedKeys.keys = [
      # Allow self-ssh from inside chroot to push binaries into host store
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDF14YFQO6wRG3D8J5a0JzqfRsFtL0azbRQimjN+9MpiNUGkv9AMA9ITcztmyJRwzwTZAKSIYOa2B9aFwNvQ/CZyFXsBt/ux18L/uRNF+xeSDOgkxo7Y8ErCdVg024/AphSM5/CEEiOotKoZKV+cYSNsgcuKnr7XY/ESc5Xm47MijxYywG1k1GNudBwxGy5D45wnKq/h1yYxCG/PyFPk2QN2PK5wnsEYhcswJ8Z54C0BcAUMvdnnMZ9v/QVqwJOfZCmhwG0Z3KTKwypmZCAqWapH+r81a7SlGyPupAdw7XK2QhWsiUqUINVyGUtYFA1GUnUiFjwjeUbpjV3xaJMFkFdzCDOtZPnYXgnCkoIwM9ZigS7wHaoSRy94o7UuHksteVKiN8WQ7ehf274NAi68u1BNKoMypjFd5B70o95q4itJ6Rn2vrCb8qC85FFyh4ueFfG4c5QkeKc/erJWQJMb0OSTeBsxV2ZXYviB/sJ0u4AY9+xgfVwCPFjVep7a9Yq94M= root@builder.arm.aws.internal"
    ];
  };
}

