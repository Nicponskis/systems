{ modulesPath, config, pkgs, lib, ... }:
let
  # TODO(Dave): Make this a flake input :(
  # agenixRoot = let
  #   commit = "b7ffcfe77f817d9ee992640ba1f270718d197f28";
  # in builtins.fetchTarball {
  #   url = "https://github.com/ryantm/agenix/archive/${commit}.tar.gz";
  #   sha256 = "00lvqwdw82jv7ngsjgnj6mv9qpr39dhcxrnycciaprwdr7jn2g22";
  # };
  agenixCLI = #pkgs.callPackage "${agenixRoot}/pkgs/agenix.nix" {};
    pkgs.age;
  # agenixModule = "${agenixRoot}/modules/age.nix";

  aws_public_ip = let
    script = pkgs.callPackage ./aws_public_ip.nix { inherit secrets; };
  in "${script}/bin/aws_public_ip";

  #s3backerLinked = pkgs.s3backer.overrideAttrs (self: {
  #  postInstall = ''ln -fs $out/bin/s3backer $out/bin/mount.s3backer'';
  #});

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

in {
  imports = [
    "${modulesPath}/virtualisation/amazon-image.nix"
    # agenixModule
  ];

  age.secrets = with lib; recursiveUpdate (mapAttrs (n: v: {file = v.cipher;}) secrets) {
    # Per-secret overrides go here
    awscli-ip_builder-pw.owner = "awscli";
    awscli-s3fs-pw.owner = "awscli";
  };

  ec2.hvm = true;
  ec2.efi = true;

  environment.systemPackages = with pkgs; [
    agenixCLI
    awscli
    compsize  # btrfs compression stats
    gitMinimal
    s3backer
    vims.minimalNormal
  ];

  # TODO(dave): Verify that this merge-conflicts.
  #boot.loader.timeout = lib.mkForce 30;
  #fileSystems."/boot".device = lib.mkForce "/dev/by-partuuid/b646b453-a2f4-6c47-96f3-d391eb353564";
  #fileSystems."/boot".device = lib.mkForce "/dev/disk/by-partuuid/b646b453-a2f4-6c47-96f3-d391eb353564";

  fileSystems."/" = lib.mkForce {
    device = "/dev/disk/by-label/nixos-btrfs";
    fsType = "btrfs";
    options = [
      "compress=zstd:3" "subvol=root"
      "nossd"
    ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-label/nixos-btrfs";
    fsType = "btrfs";
    options = [
      "noatime"
      "compress=zstd:6" "subvol=nix"
      "nossd"
    ];
  };

  fileSystems."/mnt/.s3backer" = {
    device = "${pkgs.s3backer}/bin/s3backer#vd-aarch64-nixos-builder-s3fs-001/s3backer/blocks";
    fsType = "fuse";
    noCheck = true;
    options = [
      "_netdev"
      "nofail" "rw" "noatime" #"nodiratime"
      "listBlocks"
      # Block cache for performance?
      "blockCacheFile=/var/cache/s3backer/s3dev-blockcache" "blockCacheSize=125"
      "encrypt" "sse=AES256"
      "accessFile=${secrets.awscli-s3fs-pw.plain}"
      "blockHashPrefix"
      "blockSize=2M"
      "force"  # Force mounting regardless of already-mounted flag.
      "region=us-east-1"
      #"reset-mounted-flag"
      "size=1T"
      "storageClass=INTELLIGENT_TIERING"
    ];
  };

  fileSystems."/mnt/s3fs" = {
    device = "/mnt/s3backer/file";
    fsType = "ext4";
    options = [
      "_netdev" "loop" "rw" "noatime" "nodiratime"
    ];
  };

  networking.hostName = "builder-arm-aws-internal";

  nix.gc = {
    automatic = true;
    dates = "*:0/30";  # Run a GC every 30 minutes
    persistent = true;
    randomizedDelaySec = "30sec";
  };
  nix.settings.experimental-features = ["nix-command" "flakes"];

  nixpkgs.overlays = [
    (final: prev: {
      s3backer = prev.s3backer.overrideAttrs (f2: p2: rec {
        version = "2.0.2";
        src = fetchFromGitHub {
          sha256 = "sha256-xmOtL4v3UxdjrL09sSfXyF5FoMrNerSqG9nvEuwMvNM=";
          rev = version;
        };
      });
    })
  ];

  systemd.tmpfiles.rules = [
    "d /var/cache/s3backer 0500 root root"
  ];

  services = {
    ddclient = {
      enable = true;

      domains = [ "auto.builder.arm.aws.nicponski.dev" ];

      interval = "30sec";
      passwordFile = secrets.ddclient-pw.plain;
      protocol = "googledomains";
      username = "YyIxPBXrr7Ltsxws";
    };

    openssh = {
      extraConfig = ''
        AcceptEnv LANG LC_* NIX_STORE_DIR NIX_STATE_DIR
      '';
      passwordAuthentication = false;
    };
  };

  system.stateVersion = "22.11"; # don't change unless nixos release notes say to do so!!

  systemd.services = {

  #   # TODO(Dave): Move this to a module!  (and get it actually working...)
  #   "manage-public-ip" = {
  #     description = "Acquire and release a public IP address";
  #     after = ["network-online.target" "nix-daemon.service"];
  #     #environment.NIX_PATH = "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos";
  #     #path = with pkgs; [ awscli bashInteractive curl ];
  #     requires = ["network-online.target" "nix-daemon.service"];
  #     restartIfChanged = false;
  #     startLimitBurst = 3;
  #     startLimitIntervalSec = 60;
  #     wantedBy = ["multi-user.target"];

  #     serviceConfig = {
  #       # TODO(Dave): Put this scripts into the nix store
  #       #ExecRestart = "/etc/scripts/network/aws_public_ip get";
  #       #ExecStart = "/etc/scripts/network/aws_public_ip get";
  #       ExecStart = "/run/current-system/sw/bin/echo Nothing to do at startup";
  #       ExecStop = "${aws_public_ip} drop";
  #       Group = "awscli";
  #       RemainAfterExit = true;
  #       #StandardError = "journal+console";
  #       StandardError = "journal";
  #       StandardOutput = "journal";
  #       Type = "oneshot";
  #       User = "awscli";
  #     };
  #   };
  # };

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
      ];
    };
  };
}
