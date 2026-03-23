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

      virtualisation.emptyDiskImages = [ 4096 ];
      age.identityPaths = [ config.age-mock.identityPath ];
      imports = [ inputs.age-mock-nix.nixosModules.default ];
    };
in

{
  name = "incremental";

  nodes.server = {
    imports = [
      inputs.agenix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking.hostId = "9b037621";

    systemd.services."zfs-import-spool".serviceConfig.TimeoutStartSec = "1s";

    age-mock = {
      enable = true;
      secrets.sshd_private_key.value = mock-secrets.ed25519.bob.private;
      secrets.backup_private_key.value = mock-secrets.ed25519.alice.private;
    };

    boot.initrd.postDeviceCommands = ''
      echo "encryption key" > /run/encryption_key.txt
      chmod 400 /run/encryption_key.txt
    '';
  };

  nodes.desktop = {
    imports = [
      inputs.agenix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking.hostId = "76219b03";
    ezfs.pull-backups.mybackup.enable = true;

    systemd.services."zfs-import-dpool".serviceConfig.TimeoutStartSec = "1s";

    age-mock = {
      enable = true;
      secrets.backup_private_key.value = mock-secrets.ed25519.alice.private;
    };
  };

  testScript =
    { nodes, ... }:
    ''
      start_all()

      # create
      server.wait_for_unit("multi-user.target")
      server.succeed("zpool create spool /dev/vdb")
      server.succeed("ezfs-create-myfoo")
      desktop.succeed("zpool create dpool /dev/vdb")

      # setup
      server.succeed("systemctl start --wait ezfs-mount")

      # insert initial data
      server.succeed("echo 'version 1' > /spool/foo/data.txt")

      # first backup - use manual snapshot to ensure it's captured
      server.succeed("zfs snapshot spool/foo@snap1")
      desktop.succeed("systemctl start --wait ${nodes.desktop.ezfs.pull-backups.mybackup.backupService}")

      # verify backup has the data
      desktop.succeed("zfs list -t snapshot dpool/foo_backup | grep snap1")

      # add more data
      server.succeed("echo 'version 2' > /spool/foo/data.txt")
      server.succeed("echo 'extra file' > /spool/foo/extra.txt")

      # second backup (incremental)
      server.succeed("zfs snapshot spool/foo@snap2")
      desktop.succeed("systemctl start --wait ${nodes.desktop.ezfs.pull-backups.mybackup.backupService}")

      # verify incremental backup
      desktop.succeed("zfs list -t snapshot dpool/foo_backup | grep snap2")

      # simulate data loss
      server.succeed("test -f /spool/foo/data.txt")
      server.succeed("zfs destroy -r spool/foo")
      server.fail("test -f /spool/foo/data.txt")

      # restore from latest backup
      server.succeed("ezfs-prepare-restore-pull-backup-mybackup")
      desktop.succeed("ezfs-restore-pull-backup-mybackup")

      # setup after restore
      server.succeed("systemctl start --wait ezfs-mount")

      # assert latest data is restored (version 2 from snap2)
      server.succeed("cat /spool/foo/data.txt | grep '^version 2$'")
      server.succeed("cat /spool/foo/extra.txt | grep '^extra file$'")

      # verify both snapshots were restored
      server.succeed("zfs list -t snapshot spool/foo | grep snap1")
      server.succeed("zfs list -t snapshot spool/foo | grep snap2")
    '';
}
