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
        datasets.myfoo = {
          name = "spool/foo";
          options = {
            encryption = "on";
            keyformat = "passphrase";
            keylocation = "file:///run/encryption_key.txt";
          };
        };
        pull-backups.mybackup = {
          source = "myfoo";
          host = "server";
          user = "mybackupuser";
          publicKey = builtins.readFile mockSecrets.ed25519.alice.public;
          privateKey = {
            key = "backup_ssh_key";
            # In this test, this sopsFile will be overriden by sops-mock,
            # but in production you need to provide a real sops file.
            sopsFile = config.sops-mock.secrets.backup_private_key.sopsFile;
          };
        };
      };

      # required for test only
      virtualisation.emptyDiskImages = [ 4096 ]; # add /dev/vdb
      sops.validateSopsFiles = false; # Required for allow-import-from-derivation = false;
      sops.age.keyFile = config.sops-mock.age.keyFile;
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

    # required for zfs
    networking.hostId = "9b037621";

    ezfs.datasets.myfoo.enable = true;

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
    systemd.services."zfs-import-spool".serviceConfig.TimeoutStartSec = "1s";
    boot.initrd.postDeviceCommands = ''
      echo "encryption key" > /run/encryption_key.txt
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

    ezfs.pull-backups.mybackup = {
      enable = true;
      dataset = "dpool/foo_backup";
    };

    # Required for test only
    systemd.services."zfs-import-dpool".serviceConfig.TimeoutStartSec = "1s";
    sops-mock = {
      enable = true;
      secrets.backup_private_key.value = builtins.readFile mockSecrets.ed25519.alice.private;
      secrets.backup_private_key.key = "backup_ssh_key";
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
    server.succeed("systemctl start --wait ezfs-setup-myfoo")

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
    server.succeed("ezfs-prepare-pull-restore-myfoo")

    # Restore backup
    desktop.succeed("ezfs-restore-pull-backup-mybackup")

    # Setup and mount the dataset
    server.succeed("systemctl start --wait ezfs-setup-myfoo")

    # Assert that the data is restored
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("cat /spool/foo/hello.txt | grep '^hello world$'")
  '';
}
