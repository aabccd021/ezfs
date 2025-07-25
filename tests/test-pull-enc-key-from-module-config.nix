# This test makes sure that `options.keylocation` is lazy loaded
# (only read when the dataset is enabled).
#
# We want to share ezfs config as many as possible between server and desktop,
# so ideally any options that only used by a specific node doesn't make error on another node.
#
# Specifically in this test, `environment.etc."encryption_key.txt".text` only exists on the server,
# and if we don't implement it correctly, the desktop will fail to build.

inputs:
let
  mock-secrets = inputs.mock-secrets-nix.lib.secrets;
  sharedModule =
    { config, ... }:
    {

      ezfs = {
        hosts = {
          "9b037621" = {
            publicKey = builtins.readFile mock-secrets.ed25519.bob.public;
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
            keylocation = "file://${config.environment.etc."encryption_key.txt".source}";
          };
        };
        pull-backups.mybackup = {
          targetDatasetName = "dpool/foo_backup";
          sourceDatasetId = "myfoo";
          host = "server";
          user = "mybackupuser";
          publicKey = builtins.readFile mock-secrets.ed25519.alice.public;
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

{
  name = "enc-key-from-module-config";

  nodes.server = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking.hostId = "9b037621";

    systemd.services."zfs-import-spool".serviceConfig.TimeoutStartSec = "1s";
    sops-mock = {
      enable = true;
      secrets.sshd_private_key.value = builtins.readFile mock-secrets.ed25519.bob.private;
      secrets.sshd_private_key.key = "sshd_private_key";
    };

    environment.etc."encryption_key.txt".text = "mysecretkey";

  };

  nodes.desktop = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking.hostId = "76219b03";

    ezfs.pull-backups.mybackup.enable = true;

    systemd.services."zfs-import-dpool".serviceConfig.TimeoutStartSec = "1s";

    # Required for test only
    sops-mock = {
      enable = true;
      secrets.backup_private_key.value = builtins.readFile mock-secrets.ed25519.alice.private;
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
