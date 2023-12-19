{ modulesPath, config, pkgs, lib, ... }:
let
  agenixCLI = pkgs.age;

  # aws_public_ip = let
  #   script = pkgs.callPackage ./aws_public_ip.nix { inherit secrets; };
  # in "${script}/bin/aws_public_ip";

  changedetection-io-port = 5221;

  notifyMe = pkgs.writeShellScriptBin "notify" ''
    ${pkgs.apprise}/bin/apprise -v -t "Heads up from $(${pkgs.hostname}/bin/hostname)..." -b \
      "$*" \
      'json://ntfy.sh/?+X-Priority=high&:topic=vd420__notify_01' \
      'mailto://dave.nicponski:qlnllemibmyjccyv@gmail.com?from=Dave%20Alerts<dave.nicponski@gmail.com>&to=dave.nicponski@gmail.com'
  '';

  secrets = with lib; (flip genAttrs) (n: {
    plain = config.age.secrets.${n}.path;
    cipher = ./secrets/${n}.age;
  }) [
    "awscli-ip_builder-pw"
    "awscli-s3fs-pw"
    "ddclient-pw"
    "inadyn-pw"

    "test-secret"
  ];

  vims = (import ./nix/vims.nix) { inherit pkgs lib; };
  nix-portables = (import ./nix/nix-portable.nix) { inherit pkgs lib; };

in {
  imports = [
    "${modulesPath}/virtualisation/amazon-image.nix"
    # ./nix/dwarffs.nix
  ];

  age.secrets = with lib; recursiveUpdate (mapAttrs (n: v: {file = v.cipher;}) secrets) {
    # Per-secret overrides go here
    awscli-ip_builder-pw.owner = "awscli";
    awscli-s3fs-pw.owner = "awscli";
    inadyn-pw.owner = "inadyn";
  };
  #age.secrets = {
  #  "ddclient-pw".file = ./secrets/ddclient-pw.age;
  #};

  boot.tmp.useTmpfs = true;

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
    # Essentials
    agenixCLI
    awscli
    bashInteractive
    bat
    eza
    gitMinimal  # TODO(Dave): Eliminate python here also
    htop
    mosh
    lsof
    ncdu
    # nix-portables.bootstrap
    nix-portable
    s3backer
    viddy # better `watch`
  ] ++ [
    # Really want
    #compsize  # btrfs compression stats
    file
    nix-tree # Help with space analysis
    nvd  # Compare sizes & versions of two system closures
    vims.minimalNormal
  ] ++ [
    # Dave's additions
    notifyMe
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
    53  # DNS
  ];
  networking.firewall.allowedUDPPortRanges = [
    { from = 53; to = 53; } # DNS
    { from = 60000; to = 61000; } # mosh
  ];
  networking.hostName = "arm-builder-west";

  nix.gc = {
    automatic = true;
    dates = "daily";
    persistent = true;
    randomizedDelaySec = "3600sec";
  };

  nix.generateRegistryFromInputs = false;
  # # Shrink this system closure!!  It appears that all inputs
  # # to the flake will be included by default.
  # # TODO(Dave): Maybe include just the nixpkgs one?
  # nix.registry = lib.mkForce { };

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
    certs = { };
    defaults = {
      email = "dave.nicponski+acme.certs@gmail.com";
      # `nginx` needs to be able to access these certs!
      group = config.users.users.nginx.group;
    };
  };

  services.ddclient = {
    enable = true;

    domains = [ "west.builder.arm.aws.nicponski.dev" ];

    interval = "30sec";
    passwordFile = secrets.ddclient-pw.plain;
    protocol = "googledomains";
    username = "tsDqVBmzF2UmhpUb";
  };

  services.networking.inadyn = {
    enable = true;

    configFileContents = ''
      period = 60
      user-agent = Mozilla/5.0
     '';
     providers."domains.google.com" = {
      hostname = "west.builder.arm.aws.nicponski.dev";
      passwordFile = secrets.inadyn-pw.plain;
      username = "tsDqVBmzF2UmhpUb";
     };
  };

  services.openssh.settings.PasswordAuthentication = false;

  swapDevices = [
    { device = "/dev/disk/by-uuid/fcd5007d-b1e8-42d4-b5b7-66228278a648"; }  # 4GB
  ];

  system.stateVersion = "22.11"; # don't change unless nixos release notes say to do so!!

  systemd.services = { };

  systemd.tmpfiles.rules = [
    "d /var/cache/s3backer 0700 root root"
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

    users."builder" = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCqsa5ccTCbVGKxZdupKYkkNKch6MPaahPSfVYJa0fa9Eoj44T0Cz5pcnOorjHekKOTGJDU817vYZ2b9a7TsXuEGmJNOMzubn7jpydOoUkq826Hpa8RJUCkygxL7j2EZsm0h8FXKgB7Xbz39x9POG7Zrs5M3kCHVSr8MMSXEvjNIV81e1AR4lDOM3mlb0qpMB0AXkt0vEO+aEHBc4BkS4ff5i63AdN5TcEr/sQW1WpPdnnkmmnToHRtDI1AA/cDP6pOzw8ONcK1/J9W1vkWz7zW/kSFkeu91zoSBImRNelwZM6gJ580XzgWdeqDK5Q6u1x4lrlwtgWlDqOpZ2syphhwTuJIHGgr3YBYHr7nzCJ43RS0qG8M8wsS3n0BrRy+fTCatVYgJGKxnfNuzynTp3NYJjjVgZonTKDDzdlFakf6GEfekwJLX2wkTlSonBuWyzjVxn249HUBwKFz8hFyymbUWNWPu8Fv7hRtJrKWvrHOnIR0SVZoArO/mug9LeYZSrM= dave@lidjamoypi"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC3byObhoiui0p3ot+Dh/d5W1olb6g0oLYoQlqts1fjgxTsdJSqmjnlpkAC0SohZjERXRSIndwHeHkoFI875P9t3gJSbkRXTJ78WsiGmqYVYcJ87/aS6RIDRx8/2aHIorJMxYCv0WtytbDBXhPFosITT4jUhSRObFfAo5DfWnfnaiVO+AERP67XHT+mDQm/rz2lNIeqambkXQRcs0itFeuvoPTCuV6pGtzEoZRxFzPKubZHMVqoH2GJyXL5yGjO0Z2drKFYg6ZnQ3mTEecd+MLIaRpdEb2uAczdl9pR+d4BltCT9jS+N3OLrB3TM0tdxAdqk+vK06/aYiczZzKyMqlAAa04Vj9sdD5lUYm9az69z9FYnCZ84L4jPKUdpteLV7lwzbC/RTDW7a8aXeitrL6fwGbLTYeaHgK79WN6T4dlxKi7cnjRviLmpBSask/CxoDGvnIinuZIVWbSndl4MHQbfM63btNo32TIRdYB52n/tgss3p5euH8z3NQ51k/GZjE= root@lidjamoypi"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCi+GbiMk0UqGYfG+7jmTGaKRtIVTFBwVG0p6kg3l4rsG2S7LCBG9MAgMQQKCfBay1SdXVZvr8wrc7TMj2dk0ZrnQklBd7Cn6hXE3rOiIa+1FFAtXfI4r6gMhzIa91uF63okW09wPYCUxUYmhNSGwC1rTytU5SE1jf5o/Asp/ZfHvmxhm5EUxw5qacS/Ilf4OhEWyQaQG6xeHnO4NCGThIpdTxC2Q9LpQAPlz6lZedEWTTLcXRTcG+olhxfudQ/JMdzQhqluVRCOgolIS32rvKi9st7H3D6q2sZH8MNnbl22FQNHg8f4fl34L1X/n/Zf6573eL0V5uKEtdachwrN+X5FUgwwzn7ivHjAxOHVHuWuADk+HVCG95zN1eyPLbCR8FwF/LtfjfQiF6Erwd3mNdjMK9J1upAfZkix7Ap8UDi2qmK5fzWNXcvFV7bFSo8kRd7ztMRUzHU7iTynRBUGhQel0+S27oMkOrf8yucvEWwf6dq064IleQEjronyweUmLgcSIWrxZJcLohnruleJzSz1MngZ8lsccMNGQys1D1ycayYirMFqBneNnRPtpaqesy9aADvxyzCvp69DogeJEfe++FGGVaKijxRc//EwCqqSyaie+eH1+eVMva+QN3G3yjNgIiNo3ztc60hqQq0sG/K447zHuyr5xFc54fYFv2ZwQ== dave.nicponski@gmail.com davembp2"
      ];
    };

    users."root".openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCi+GbiMk0UqGYfG+7jmTGaKRtIVTFBwVG0p6kg3l4rsG2S7LCBG9MAgMQQKCfBay1SdXVZvr8wrc7TMj2dk0ZrnQklBd7Cn6hXE3rOiIa+1FFAtXfI4r6gMhzIa91uF63okW09wPYCUxUYmhNSGwC1rTytU5SE1jf5o/Asp/ZfHvmxhm5EUxw5qacS/Ilf4OhEWyQaQG6xeHnO4NCGThIpdTxC2Q9LpQAPlz6lZedEWTTLcXRTcG+olhxfudQ/JMdzQhqluVRCOgolIS32rvKi9st7H3D6q2sZH8MNnbl22FQNHg8f4fl34L1X/n/Zf6573eL0V5uKEtdachwrN+X5FUgwwzn7ivHjAxOHVHuWuADk+HVCG95zN1eyPLbCR8FwF/LtfjfQiF6Erwd3mNdjMK9J1upAfZkix7Ap8UDi2qmK5fzWNXcvFV7bFSo8kRd7ztMRUzHU7iTynRBUGhQel0+S27oMkOrf8yucvEWwf6dq064IleQEjronyweUmLgcSIWrxZJcLohnruleJzSz1MngZ8lsccMNGQys1D1ycayYirMFqBneNnRPtpaqesy9aADvxyzCvp69DogeJEfe++FGGVaKijxRc//EwCqqSyaie+eH1+eVMva+QN3G3yjNgIiNo3ztc60hqQq0sG/K447zHuyr5xFc54fYFv2ZwQ== dave.nicponski@gmail.com davembp2"
    ];
  };
}

