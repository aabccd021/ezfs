{
  pkgs,
  inputs,
  mockSecrets,
  ...
}:
let
  sharedModule =
    { config, ... }:
    {
      boot.supportedFilesystems = [ "zfs" ];

      ezfs = {
        sshdPublicKey = builtins.readFile mockSecrets.ed25519.bob.public;
        datasets."spool/foo" = {
          options = {
            encryption = "on";
            keyformat = "passphrase";
            keylocation = "file://${config.environment.etc."encryption_key.txt".source}";
          };
          pull-backup.mybackup = {
            host = "server.com";
            user = "mybackupuser";
            publicKey = builtins.readFile mockSecrets.ed25519.alice.public;
            privateKeySopsName = "ezfs_private_key";
            privateKey = {
              key = "name_of_key";
              # In this test, this sopsFile will be overriden by sops-mock,
              # but in production you need to provide a real sops file.
              sopsFile = ../secrets.yaml;
            };
          };
        };
      };

      # required for test only
      virtualisation.emptyDiskImages = [ 4096 ]; # add /dev/vdb
      sops.validateSopsFiles = false; # Required for allow-import-from-derivation = false;
    };
in

pkgs.testers.runNixOSTest {
  name = "simple-encrypted";

  nodes.server = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking = {
      # required for zfs
      hostId = "9b037621";

      # make the server accessible via domain `server.com` on NixOS VM test
      domain = "com";
    };

    # Take a snapshot every hour, and retain last 3 snapshots.
    services.sanoid = {
      enable = true;
      datasets."spool/foo".hourly = 3;
    };

    ezfs.datasets."spool/foo".enable = true;

    services.openssh = {
      enable = true;
      hostKeys = [
        {
          path = "/run/sshd_host_key";
          type = "ed25519";
        }
      ];
    };

    systemd.services."zfs-import-spool".serviceConfig.TimeoutStartSec = "1s";

    environment.etc."encryption_key.txt".text = "mysecretkey";

    # simulate putting secrets
    boot.initrd.postDeviceCommands = ''
      chmod 400 /run/encryption_key.txt
      cp -Lr ${mockSecrets.ed25519.bob.private} /run/sshd_host_key
      chmod 400 /run/sshd_host_key
    '';

  };

  nodes.desktop = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule

      # Required for test only
      inputs.sops-nix-mock.nixosModules.default
    ];

    networking.hostId = "76219b03";

    ezfs.datasets."spool/foo".pull-backup.mybackup = {
      enable = true;
      targetDataset = "dpool/foo_backup";
    };

    systemd.services."zfs-import-dpool".serviceConfig.TimeoutStartSec = "1s";

    # Required for test only
    sops-mock = {
      enable = true;
      secrets.ezfs_private_key = builtins.readFile mockSecrets.ed25519.alice.private;
    };
  };

  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")

    # Create a zpool on the server
    server.succeed("zpool create spool /dev/vdb")

    # Create a dataset based on ezfs configuration
    server.succeed("ezfs-create-spool-foo")

    # Create a zpool on the desktop
    desktop.succeed("zpool create dpool /dev/vdb")

    # Setup and mount the dataset
    server.succeed("systemctl start --wait ezfs-setup-spool-foo")

    # Insert data to the dataset
    server.succeed("echo 'hello world' > /spool/foo/hello.txt")

    # Create a snapshot of the dataset
    server.succeed("systemctl start --wait sanoid")

    # Pull backup from the server.
    # This service will run periodically, but here we run it manually for testing.
    desktop.succeed("systemctl start --wait syncoid-pull-backup-spool-foo")

    # Simulate data loss
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("zfs destroy -r spool/foo")
    server.fail("test -f /spool/foo/hello.txt")

    # Grant permissions required for restoring backup.
    server.succeed("ezfs-prepare-pull-restore-spool-foo")

    # Restore backup
    desktop.succeed("ezfs-restore-spool-foo")

    # Setup and mount the dataset
    server.succeed("systemctl start --wait ezfs-setup-spool-foo")

    # Assert that the data is restored
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("cat /spool/foo/hello.txt | grep '^hello world$'")
  '';
}
