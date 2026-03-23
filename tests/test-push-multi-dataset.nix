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
        datasets.myshallow = {
          name = "spool/shallow";
          hostId = "9b037621";
          options = {
            mountpoint = "/shallow";
          };
        };
        datasets.myfoo = {
          name = "spool/foo";
          hostId = "9b037621";
          options = {
            encryption = "on";
            keyformat = "passphrase";
            keylocation = "file:///run/encryption_key.txt";
            mountpoint = "/shallow/foo";
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
  name = "push-multi-dataset";

  nodes.server =
    { ... }:
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

      # create hello before mounting anything
      server.wait_for_unit("multi-user.target")
      server.succeed("mkdir -p /shallow/foo")
      server.succeed("echo 'not zfs' > /shallow/foo/hello.txt")

      # create zpools
      server.succeed("zpool create spool /dev/vdb")
      vps.succeed("zpool create vpool /dev/vdb")

      # create datasets
      server.succeed("ezfs-create-myfoo")
      server.succeed("ezfs-create-myshallow")

      # setup on vps
      vps.succeed("systemctl start --wait ezfs-setup-push-backup")

      # setup datasets (myfoo depends on myshallow)
      server.succeed("systemctl start --wait ezfs-mount")

      # insert data
      server.succeed("echo 'foo' > /shallow/foo/hello.txt")

      # backup
      server.succeed("systemctl start --wait sanoid")
      server.succeed("systemctl start --wait ${nodes.server.ezfs.push-backups.mybackup.backupService}")

      # simulate data loss
      server.succeed("test -f /shallow/foo/hello.txt")
      server.succeed("zfs destroy -r spool/foo")
      server.fail("test -f /shallow/foo/hello.txt")

      # insert to shallow dataset
      server.succeed("echo 'shallow' > /shallow/foo/hello.txt")

      # restore
      vps.succeed("ezfs-prepare-restore-push-backup-mybackup")
      server.succeed("ezfs-restore-push-backup-mybackup")

      # setup dataset
      server.succeed("systemctl start --wait ezfs-mount")

      # assert foo dataset data is restored
      server.succeed("test -f /shallow/foo/hello.txt")
      server.succeed("cat /shallow/foo/hello.txt | grep '^foo$'")

      # unmount foo and check shallow dataset
      server.succeed("zfs unmount spool/foo")
      server.succeed("cat /shallow/foo/hello.txt | grep '^shallow$'")

      # unmount shallow and check non-zfs hello.txt
      server.succeed("zfs unmount spool/shallow")
      server.succeed("cat /shallow/foo/hello.txt | grep '^not zfs$'")
    '';
}
