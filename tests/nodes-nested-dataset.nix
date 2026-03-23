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
        # Parent dataset at /data
        datasets.parent = {
          name = "spool/parent";
          hostId = "9b037621";
          options = {
            mountpoint = "/data";
            encryption = "on";
            keyformat = "passphrase";
            keylocation = "file:///run/parent_key.txt";
          };
        };
        # Child dataset (nested in ZFS) at /data/child
        # Must depend on parent so parent mounts first
        datasets.child = {
          name = "spool/parent/child";
          hostId = "9b037621";
          dependsOn = [ "parent" ];
          options = {
            mountpoint = "/data/child";
            encryption = "on";
            keyformat = "passphrase";
            keylocation = "file:///run/child_key.txt";
          };
        };
        pull-backups.mybackup-parent = {
          targetDatasetName = "dpool/parent_backup";
          sourceDatasetId = "parent";
          host = "server";
          user = "mybackupuser";
          publicKey = mock-secrets.ed25519.alice.public;
          privateKey = config.age-mock.secrets.backup_private_key.file;
        };
        pull-backups.mybackup-child = {
          targetDatasetName = "dpool/child_backup";
          sourceDatasetId = "child";
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
  server = {
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
    };

    boot.initrd.postDeviceCommands = ''
      echo "parent key" > /run/parent_key.txt
      chmod 400 /run/parent_key.txt
      echo "child key" > /run/child_key.txt
      chmod 400 /run/child_key.txt
    '';
  };

  desktop = {
    imports = [
      inputs.agenix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking.hostId = "76219b03";

    ezfs.pull-backups.mybackup-parent.enable = true;
    ezfs.pull-backups.mybackup-child.enable = true;

    systemd.services."zfs-import-dpool".serviceConfig.TimeoutStartSec = "1s";

    age-mock = {
      enable = true;
      secrets.backup_private_key.value = mock-secrets.ed25519.alice.private;
    };
  };
}
