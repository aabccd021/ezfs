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
        # Encrypted parent at /data
        datasets.encrypted = {
          name = "spool/encrypted";
          hostId = "9b037621";
          options = {
            mountpoint = "/data";
            encryption = "on";
            keyformat = "passphrase";
            keylocation = "file:///run/encryption_key.txt";
          };
        };
        # Child at /data/child (with different key)
        datasets.unencrypted = {
          name = "spool/unencrypted";
          hostId = "9b037621";
          dependsOn = [ "encrypted" ];
          options = {
            mountpoint = "/data/child";
            encryption = "on";
            keyformat = "passphrase";
            keylocation = "file:///run/unencrypted_key.txt";
          };
        };
        pull-backups.mybackup-encrypted = {
          targetDatasetName = "dpool/encrypted_backup";
          sourceDatasetId = "encrypted";
          host = "server";
          user = "mybackupuser";
          publicKey = mock-secrets.ed25519.alice.public;
          privateKey = config.age-mock.secrets.backup_private_key.file;
        };
        pull-backups.mybackup-unencrypted = {
          targetDatasetName = "dpool/unencrypted_backup";
          sourceDatasetId = "unencrypted";
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
      secrets.backup_private_key.value = mock-secrets.ed25519.alice.private;
    };

    boot.initrd.postDeviceCommands = ''
      echo "encryption key" > /run/encryption_key.txt
      chmod 400 /run/encryption_key.txt
      echo "unencrypted key" > /run/unencrypted_key.txt
      chmod 400 /run/unencrypted_key.txt
    '';
  };

  desktop = {
    imports = [
      inputs.agenix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking.hostId = "76219b03";

    ezfs.pull-backups.mybackup-encrypted.enable = true;
    ezfs.pull-backups.mybackup-unencrypted.enable = true;

    systemd.services."zfs-import-dpool".serviceConfig.TimeoutStartSec = "1s";

    age-mock = {
      enable = true;
      secrets.backup_private_key.value = mock-secrets.ed25519.alice.private;
    };
  };
}
