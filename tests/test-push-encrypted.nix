inputs:
let
  mock-secrets = inputs.mock-secrets-nix.lib.secrets;
  sharedModule =
    { config, ... }:
    {

      ezfs = {
        hosts = {
          "76219b03" = {
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
        push-backups.mybackup = {
          targetDatasetName = "vpool/foo_backup";
          sourceDatasetId = "myfoo";
          hostId = "76219b03";
          host = "vps";
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
  name = "push-encrypted";

  nodes.server =
    { config, ... }:
    {
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
        secrets.backup_private_key.value = mock-secrets.ed25519.alice.private;
      };

      assertions =
        let
          sanoid_datasets = builtins.attrNames config.services.sanoid.datasets;
        in
        [
          {
            assertion = builtins.length sanoid_datasets == 1;
            message = "sanoid should only have one dataset";
          }
          {
            assertion = builtins.elemAt sanoid_datasets 0 == "spool/foo";
            message = "sanoid dataset should be 'spool/foo', got: ${builtins.elemAt sanoid_datasets 0}";
          }
        ];
    };

  nodes.vps = {
    imports = [
      inputs.agenix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking.hostId = "76219b03";

    ezfs.push-backups.mybackup.enable = true;

    # Required for test only
    systemd.services."zfs-import-vpool".serviceConfig.TimeoutStartSec = "1s";
    age-mock = {
      enable = true;
      secrets.sshd_private_key.value = mock-secrets.ed25519.bob.private;
    };
  };

  testScript =
    { nodes, ... }:
    ''
      start_all()
      server.wait_for_unit("multi-user.target")

      # Create a zpool on the server
      server.succeed("zpool create spool /dev/vdb")

      # Create a dataset based on ezfs configuration
      server.succeed("ezfs-create-myfoo")

      # Create a zpool on the vps
      vps.succeed("zpool create vpool /dev/vdb")

      # Setup on vps
      vps.succeed("systemctl start --wait ezfs-setup-push-backup-mybackup")

      # Setup and mount the dataset
      server.succeed("systemctl start --wait ezfs-mount")

      # Insert data to the dataset
      server.succeed("echo 'hello world' > /spool/foo/hello.txt")

      # Create a snapshot of the dataset
      server.succeed("systemctl start --wait sanoid")

      # Push backup to the vps
      # This service will run periodically, but here we run it manually for testing.
      server.succeed("systemctl start --wait ${nodes.server.ezfs.push-backups.mybackup.backupService}")

      # Simulate data loss
      server.succeed("test -f /spool/foo/hello.txt")
      server.succeed("zfs destroy -r spool/foo")
      server.fail("test -f /spool/foo/hello.txt")

      # Restore backup
      vps.succeed("ezfs-prepare-restore-push-backup-mybackup")
      server.succeed("ezfs-restore-push-backup-mybackup")

      # Setup and mount the dataset
      server.succeed("systemctl start --wait ezfs-mount")

      # Assert that the data is restored
      server.succeed("test -f /spool/foo/hello.txt")
      server.succeed("cat /spool/foo/hello.txt | grep '^hello world$'")
    '';
}
