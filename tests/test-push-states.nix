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
          user = "myserveruser";
          group = "myservergroup";
          options = {
            encryption = "on";
            keyformat = "passphrase";
            keylocation = "file:///run/encryption_key.txt";
            devices = "off";
            setuid = "off";
            exec = "off";
            compression = "zstd";
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
  name = "push-states";

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

      users.users.myserveruser.isNormalUser = true;
      users.groups.myservergroup = { };

      # simulate putting secrets
      boot.initrd.postDeviceCommands = ''
        echo "encryption key" > /run/encryption_key.txt
        chmod 400 /run/encryption_key.txt
      '';

      # Required for test only
      systemd.services."zfs-import-spool".serviceConfig.TimeoutStartSec = "1s";
      age-mock = {
        enable = true;
        secrets.sshd_private_key.value = mock-secrets.ed25519.bob.private;
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
      secrets.backup_private_key.value = mock-secrets.ed25519.alice.private;
    };
  };

  testScript =
    { nodes, ... }:
    ''
      def assert_server():
          server.succeed("zfs get -H -o value compression spool/foo | grep '^zstd$'")
          server.succeed("zfs get -H -o value setuid spool/foo | grep '^off$'")
          server.succeed("zfs get -H -o value exec spool/foo | grep '^off$'")
          server.succeed("zfs get -H -o value devices spool/foo | grep '^off$'")
          server.succeed("stat -c '%U:%G' /spool/foo | grep '^myserveruser:myservergroup$'")

      start_all()
      server.wait_for_unit("multi-user.target")

      # Create zpools
      server.succeed("zpool create spool /dev/vdb")
      vps.succeed("zpool create vpool /dev/vdb")

      # Create dataset
      server.succeed("ezfs-create-myfoo")

      # Setup on vps
      vps.succeed("systemctl start --wait ezfs-setup-push-backup")

      # Setup dataset
      server.succeed("systemctl start --wait ezfs-mount")
      assert_server()

      # Insert data
      server.succeed("echo 'hello world' > /spool/foo/hello.txt")

      # Backup
      server.succeed("systemctl start --wait sanoid")
      server.succeed("systemctl start --wait ${nodes.server.ezfs.push-backups.mybackup.backupService}")

      # Simulate data loss
      server.succeed("test -f /spool/foo/hello.txt")
      server.succeed("zfs destroy -r spool/foo")
      server.fail("test -f /spool/foo/hello.txt")

      # Restore
      vps.succeed("ezfs-prepare-restore-push-backup-mybackup")
      server.succeed("ezfs-restore-push-backup-mybackup")

      # Setup dataset after restore
      server.succeed("systemctl start --wait ezfs-mount")
      assert_server()

      # Assert data restored
      server.succeed("test -f /spool/foo/hello.txt")
      server.succeed("cat /spool/foo/hello.txt | grep '^hello world$'")
    '';
}
