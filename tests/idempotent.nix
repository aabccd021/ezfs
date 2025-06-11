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
        sshdPrivateKey = {
          sopsFile = config.sops-mock.secrets.sshd_private_key.sopsFile;
          key = "sshd_private_key";
        };
        datasets.myfoo = {
          name = "spool/foo";
          options = {
            encryption = "on";
            keyformat = "passphrase";
            keylocation = "file:///run/encryption_key.txt";
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

pkgs.testers.runNixOSTest {
  name = "idempotent";

  nodes.server = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking.hostId = "9b037621";

    ezfs.datasets.myfoo.enable = true;

    boot.initrd.postDeviceCommands = ''
      echo "encryption key" > /run/encryption_key.txt
      chmod 400 /run/encryption_key.txt
    '';

    systemd.services."zfs-import-spool".serviceConfig.TimeoutStartSec = "1s";
    sops-mock = {
      enable = true;
      secrets.sshd_private_key.value = builtins.readFile mockSecrets.ed25519.bob.private;
      secrets.sshd_private_key.key = "sshd_private_key";
    };

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

    sops-mock = {
      enable = true;
      secrets.backup_private_key.value = builtins.readFile mockSecrets.ed25519.alice.private;
      secrets.backup_private_key.key = "backup_ssh_key";
    };
  };

  testScript = ''
    server.start(allow_reboot=True)
    desktop.start(allow_reboot=True)

    # create
    server.wait_for_unit("multi-user.target")
    server.succeed("zpool create spool /dev/vdb")
    server.succeed("ezfs-create-myfoo")
    desktop.succeed("zpool create dpool /dev/vdb")

    # setup
    server.succeed("systemctl start --wait ezfs-setup-myfoo")

    # insert data
    server.succeed("echo 'hello world' > /spool/foo/hello.txt")
    server.succeed("systemctl start --wait ezfs-setup-myfoo")

    # backup
    server.succeed("systemctl start --wait sanoid")
    desktop.succeed("systemctl start --wait syncoid-pull-backup-mybackup")
    server.succeed("systemctl start --wait ezfs-setup-myfoo")

    # destroy
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("zfs destroy -r spool/foo")
    server.fail("test -f /spool/foo/hello.txt")

    # restore
    server.succeed("ezfs-prepare-restore-pull-backup-mybackup")
    desktop.succeed("ezfs-restore-pull-backup-mybackup")

    # setup
    server.succeed("systemctl start --wait ezfs-setup-myfoo")

    # assert
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("cat /spool/foo/hello.txt | grep '^hello world$'")
    server.succeed("systemctl start --wait ezfs-setup-myfoo")
  '';
}
