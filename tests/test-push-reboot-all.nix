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
  name = "push-reboot-all";

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
      server.start(allow_reboot=True)
      vps.start(allow_reboot=True)

      # create
      server.wait_for_unit("multi-user.target")
      server.succeed("zpool create spool /dev/vdb")
      server.succeed("ezfs-create-myfoo")
      vps.succeed("zpool create vpool /dev/vdb")

      # reboot
      server.reboot()
      vps.reboot()
      server.wait_for_unit("multi-user.target")
      vps.wait_for_unit("multi-user.target")

      # insert data
      server.succeed("echo 'hello world' > /spool/foo/hello.txt")

      # backup
      server.succeed("systemctl start --wait sanoid")
      server.succeed("systemctl start --wait ${nodes.server.ezfs.push-backups.mybackup.backupService}")

      # reboot
      server.reboot()
      vps.reboot()
      server.wait_for_unit("multi-user.target")
      vps.wait_for_unit("multi-user.target")

      # destroy
      server.succeed("test -f /spool/foo/hello.txt")
      server.succeed("zfs destroy -r spool/foo")
      server.fail("test -f /spool/foo/hello.txt")

      # reboot
      server.reboot()
      vps.reboot()
      server.wait_for_unit("multi-user.target")
      vps.wait_for_unit("multi-user.target")

      # restore
      vps.succeed("ezfs-prepare-restore-push-backup-mybackup")
      server.succeed("ezfs-restore-push-backup-mybackup")

      # reboot
      server.reboot()
      server.wait_for_unit("multi-user.target")

      # assert
      server.succeed("test -f /spool/foo/hello.txt")
      server.succeed("cat /spool/foo/hello.txt | grep '^hello world$'")
    '';
}
