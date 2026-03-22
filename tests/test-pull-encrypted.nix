inputs:
let
  mock-secrets = inputs.mock-secrets-nix.lib.secrets;

  sharedModule =
    { config, ... }:
    {

      ezfs = {
        hosts = {
          "9b037621" = {
            publicKey = mock-secrets.ed25519.bob.public;
            privateKey = config.age-mock.secrets.sshd_private_key.file;
          };
        };
        datasets.myfoo = {
          name = "spool/foo";
          hostId = "9b037621";
          options = {
            encryption = "on";
            keyformat = "passphrase";
            keylocation = "file:///run/encryption_key.txt";
          };
        };
        pull-backups.mybackup = {
          targetDatasetName = "dpool/foo_backup";
          sourceDatasetId = "myfoo";
          host = "server";
          user = "mybackupuser";
          publicKey = mock-secrets.ed25519.alice.public;
          privateKey = config.age-mock.secrets.backup_private_key.file;
        };
      };

      # required for test only
      virtualisation.emptyDiskImages = [ 4096 ]; # add /dev/vdb
      age.identityPaths = [ config.age-mock.identityPath ];
      imports = [ inputs.age-mock-nix.nixosModules.default ];
    };
in

{
  name = "encrypted";

  nodes.server = {
    imports = [
      inputs.agenix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    # required for zfs
    networking.hostId = "9b037621";

    # simulate putting secrets
    boot.initrd.postDeviceCommands = ''
      echo "encryption key" > /run/encryption_key.txt
      chmod 400 /run/encryption_key.txt
    '';

    # Required for test only
    systemd.services."zfs-import-spool".serviceConfig.TimeoutStartSec = "1s";
    age-mock = {
      enable = true;
      secrets.sshd_private_key.value = mock-secrets.ed25519.bob.private;
    };
  };

  nodes.desktop = {
    imports = [
      inputs.agenix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking.hostId = "76219b03";

    ezfs.pull-backups.mybackup.enable = true;

    # Required for test only
    systemd.services."zfs-import-dpool".serviceConfig.TimeoutStartSec = "1s";
    age-mock = {
      enable = true;
      secrets.backup_private_key.value = mock-secrets.ed25519.alice.private;
    };
  };

  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")

    # Create a zpool on the server
    server.succeed("zpool create spool /dev/vdb")

    # Create a dataset based on ezfs configuration
    server.succeed("ezfs-create-myfoo")

    # Create a zpool on the desktop
    desktop.succeed("zpool create dpool /dev/vdb")

    # Setup and mount the dataset
    server.succeed("systemctl start --wait ezfs-setup-dataset-myfoo")

    # Insert data to the dataset
    server.succeed("echo 'hello world' > /spool/foo/hello.txt")

    # Create a snapshot of the dataset
    server.succeed("systemctl start --wait sanoid")

    # Pull backup from the server.
    # This service will run periodically, but here we run it manually for testing.
    desktop.succeed("systemctl start --wait syncoid-pull-backup-mybackup")

    # Simulate data loss
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("zfs destroy -r spool/foo")
    server.fail("test -f /spool/foo/hello.txt")

    # Grant permissions required for restoring backup.
    server.succeed("ezfs-prepare-restore-pull-backup-mybackup")

    # Restore backup
    desktop.succeed("ezfs-restore-pull-backup-mybackup")

    # Setup and mount the dataset
    server.succeed("systemctl start --wait ezfs-setup-dataset-myfoo")

    # Assert that the data is restored
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("cat /spool/foo/hello.txt | grep '^hello world$'")
  '';
}
