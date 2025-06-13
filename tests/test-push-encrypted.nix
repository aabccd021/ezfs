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

      ezfs = {
        hosts = {
          "76219b03" = {
            publicKey = builtins.readFile mockSecrets.ed25519.bob.public;
            privateKey = {
              sopsFile = config.sops-mock.secrets.sshd_private_key.sopsFile;
              key = "sshd_private_key";
            };
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
          publicKey = builtins.readFile mockSecrets.ed25519.alice.public;
          privateKey = {
            key = "backup_ssh_key";
            sopsFile = config.sops-mock.secrets.backup_private_key.sopsFile;
          };
        };
      };

      # required for test only
      virtualisation.emptyDiskImages = [ 4096 ]; # add /dev/vdb
      sops.validateSopsFiles = false; # Required for allow-import-from-derivation = false;
      sops.age.keyFile = config.sops-mock.age.keyFile;
      imports = [ inputs.sops-nix-mock.nixosModules.default ];
    };
in

pkgs.testers.runNixOSTest {
  name = "push-encrypted";

  nodes.server =
    { config, ... }:
    {
      imports = [
        inputs.sops-nix.nixosModules.default
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
      sops-mock = {
        enable = true;
        secrets.backup_private_key.value = builtins.readFile mockSecrets.ed25519.alice.private;
        secrets.backup_private_key.key = "backup_ssh_key";
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
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking.hostId = "76219b03";

    ezfs.push-backups.mybackup.enable = true;

    # Required for test only
    systemd.services."zfs-import-vpool".serviceConfig.TimeoutStartSec = "1s";
    sops-mock = {
      enable = true;
      secrets.sshd_private_key.value = builtins.readFile mockSecrets.ed25519.bob.private;
      secrets.sshd_private_key.key = "sshd_private_key";
    };
  };

  testScript = ''
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
    server.succeed("systemctl start --wait ezfs-setup-dataset-myfoo")

    # Insert data to the dataset
    server.succeed("echo 'hello world' > /spool/foo/hello.txt")

    # Create a snapshot of the dataset
    server.succeed("systemctl start --wait sanoid")

    # Push backup to the vps
    # This service will run periodically, but here we run it manually for testing.
    server.succeed("systemctl start --wait syncoid-push-backup-mybackup")

    # Simulate data loss
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("zfs destroy -r spool/foo")
    server.fail("test -f /spool/foo/hello.txt")

    # Restore backup
    vps.succeed("ezfs-prepare-restore-push-backup-mybackup")
    server.succeed("ezfs-restore-push-backup-mybackup")

    # Setup and mount the dataset
    server.succeed("systemctl start --wait ezfs-setup-dataset-myfoo")

    # Assert that the data is restored
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("cat /spool/foo/hello.txt | grep '^hello world$'")
  '';
}
