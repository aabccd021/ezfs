{
  pkgs,
  inputs,
  mockSecrets,
  ...
}:
let
  sharedModule = {
    boot.supportedFilesystems = [ "zfs" ];

    ezfs = {
      sshdPublicKey = builtins.readFile mockSecrets.ed25519.bob.public;
      datasets."zpool/foo" = {
        options = {
          encryption = "on";
          keyformat = "passphrase";
        };
        pull-backup.mybackup = {
          host = "server.com";
          user = "mybackupuser";
          publicKey = builtins.readFile mockSecrets.ed25519.alice.public;
          privateKey = {
            sopsFile = ../secrets.yaml;
            key = "name_of_key";
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
  name = "test01";

  nodes.server = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking = {
      hostId = "9b037621";
      domain = "com";
    };

    services.sanoid = {
      enable = true;
      datasets."zpool/foo" = { };
    };

    ezfs.datasets."zpool/foo" = {
      enable = true;
      options.keylocation = "file:///run/encryption_key.txt";
    };

    services.openssh = {
      enable = true;
      hostKeys = [
        {
          path = "/run/sshd_host_key";
          type = "ed25519";
        }
      ];
    };

    # simulate putting secrets
    boot.initrd.postDeviceCommands = ''
      echo "encryption key" > /run/encryption_key.txt
      cp -Lr ${mockSecrets.ed25519.bob.private} /run/sshd_host_key
      chmod -R 400 /run/sshd_host_key
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

    ezfs.datasets."zpool/foo".pull-backup.mybackup = {
      enable = true;
      targetDataset = "backup_zpool/foo_backup";
    };

    # Required for test only
    sops-mock = {
      enable = true;
      secrets.ezfs_pull_backup_zpool_foo = builtins.readFile mockSecrets.ed25519.alice.private;
    };
  };

  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")

    # Create a zpool on the server
    server.succeed("zpool create zpool /dev/vdb")

    # Create a dataset based on ezfs configuration
    server.succeed("ezfs-create-zpool-foo")

    # Setup and mount the dataset
    server.succeed("systemctl start --wait ezfs-setup-zpool-foo")

    # Insert data to the dataset
    server.succeed("echo 'hello world' > /zpool/foo/hello.txt")

    # Create a snapshot of the dataset
    server.succeed("systemctl start --wait sanoid")

    # Create a zpool on the desktop
    desktop.succeed("zpool create backup_zpool /dev/vdb")

    # Pull backup from the server.
    # This service will run periodically, but here we run it manually for testing.
    desktop.succeed("systemctl start --wait syncoid-pull-backup-zpool-foo")

    # Simulate data loss
    server.succeed("test -f /zpool/foo/hello.txt")
    server.succeed("zfs destroy -r zpool/foo")
    server.fail("test -f /zpool/foo/hello.txt")

    # Grant permissions required for restoring backup.
    # TODO: make this a command
    server.succeed("zfs allow -u mybackupuser create,receive,mount zpool")

    # Restore backup
    desktop.succeed("syncoid-pull-restore-zpool-foo")

    # Remove permissions required for restoring backup. Optional, but best practice.
    # TDOO: do this on setup
    server.succeed("zfs unallow -u mybackupuser create,receive,mount zpool")

    # Setup and mount the dataset
    server.succeed("systemctl start --wait ezfs-setup-zpool-foo")

    # Assert that the data is restored
    server.succeed("test -f /zpool/foo/hello.txt")
    server.succeed("cat /zpool/foo/hello.txt | grep '^hello world$'")
  '';
}
