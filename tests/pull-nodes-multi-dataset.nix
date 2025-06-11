{
  inputs,
  mockSecrets,
}:
let
  sharedModule =
    { config, ... }:
    {
      boot.supportedFilesystems = [ "zfs" ];

      ezfs = {
        sshdPublicKey = builtins.readFile mockSecrets.ed25519.bob.public;
        sshdPrivateKey = {
          sopsFile = config.sops-mock.secrets.sshd_private_key.sopsFile;
          key = "sshd_private_key";
        };
        datasets.myshallow = {
          name = "spool/shallow";
          options = {
            mountpoint = "/shallow";
          };
        };
        datasets.myfoo = {
          dependsOn = [ "myshallow" ];
          name = "spool/foo";
          options = {
            encryption = "on";
            keyformat = "passphrase";
            keylocation = "file:///run/encryption_key.txt";
            mountpoint = "/shallow/foo";
          };
        };
        pull-backups.mybackup = {
          dataset = "dpool/foo_backup";
          source = "myfoo";
          host = "server";
          user = "mybackupuser";
          publicKey = builtins.readFile mockSecrets.ed25519.alice.public;
          privateKey = {
            key = "backup_ssh_key";
            sopsFile = config.sops-mock.secrets.backup_private_key.sopsFile;
          };
        };
      };

      virtualisation.emptyDiskImages = [ 4096 ];
      sops.validateSopsFiles = false;
      sops.age.keyFile = config.sops-mock.age.keyFile;
      imports = [ inputs.sops-nix-mock.nixosModules.default ];
    };
in

{
  server = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking.hostId = "9b037621";

    ezfs.datasets.myshallow.enable = true;

    ezfs.datasets.myfoo.enable = true;

    systemd.services."zfs-import-spool".serviceConfig.TimeoutStartSec = "1s";
    sops-mock = {
      enable = true;
      secrets.sshd_private_key.value = builtins.readFile mockSecrets.ed25519.bob.private;
      secrets.sshd_private_key.key = "sshd_private_key";
    };

    boot.initrd.postDeviceCommands = ''
      echo "encryption key" > /run/encryption_key.txt
      chmod 400 /run/encryption_key.txt
    '';

  };

  desktop = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking.hostId = "76219b03";

    ezfs.pull-backups.mybackup.enable = true;

    systemd.services."zfs-import-dpool".serviceConfig.TimeoutStartSec = "1s";

    sops-mock = {
      enable = true;
      secrets.backup_private_key.value = builtins.readFile mockSecrets.ed25519.alice.private;
      secrets.backup_private_key.key = "backup_ssh_key";
    };
  };
}
