inputs:
let
  mock-secrets = inputs.mock-secrets-nix.lib.secrets;

  ezfsConfig =
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

    };

  serverTestConfig =
    { config, ... }:
    {
      imports = [
        inputs.age-mock-nix.nixosModules.default
      ];
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
      virtualisation.emptyDiskImages = [ 4096 ];
      age.identityPaths = [ config.age-mock.identityPath ];
    };

  desktopTestConfig =
    { config, ... }:
    {
      imports = [
        inputs.age-mock-nix.nixosModules.default
      ];
      systemd.services."zfs-import-dpool".serviceConfig.TimeoutStartSec = "1s";
      age-mock = {
        enable = true;
        secrets.backup_private_key.value = mock-secrets.ed25519.alice.private;
      };
      virtualisation.emptyDiskImages = [ 4096 ];
      age.identityPaths = [ config.age-mock.identityPath ];
    };

in

{

  server = {
    imports = [
      inputs.agenix.nixosModules.default
      inputs.ezfs.nixosModules.default
      ezfsConfig

      serverTestConfig # only required in test
    ];

    networking.hostId = "9b037621";

  };

  desktop = {
    imports = [
      inputs.agenix.nixosModules.default
      inputs.ezfs.nixosModules.default
      ezfsConfig

      desktopTestConfig # only required in test
    ];

    networking.hostId = "76219b03";
    ezfs.pull-backups.mybackup.enable = true;

  };
}
