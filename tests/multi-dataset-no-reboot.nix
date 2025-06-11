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
    };
in

pkgs.testers.runNixOSTest {
  name = "multi-dataset-no-reboot";

  nodes.server = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking.hostId = "9b037621";

    ezfs.datasets.myshallow.enable = true;

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
      inputs.sops-nix-mock.nixosModules.default
    ];

    networking.hostId = "76219b03";

    ezfs.pull-backups.mybackup = {
      enable = true;
      dataset = "dpool/foo_backup";
    };

    systemd.services."zfs-import-dpool".serviceConfig.TimeoutStartSec = "1s";

    sops-mock = {
      enable = true;
      secrets.backup_private_key.value = builtins.readFile mockSecrets.ed25519.alice.private;
      secrets.backup_private_key.key = "backup_ssh_key";
    };
  };

  testScript = ''
    start_all()

    # create hello before mounting anything
    server.wait_for_unit("multi-user.target")
    server.succeed("mkdir -p /shallow/foo")
    server.succeed("echo 'not zfs' > /shallow/foo/hello.txt")

    # create
    server.succeed("zpool create spool /dev/vdb")
    server.succeed("ezfs-create-myfoo")
    server.succeed("ezfs-create-myshallow")
    desktop.succeed("zpool create dpool /dev/vdb")

    # setup
    server.succeed("systemctl start --wait ezfs-setup-myfoo")

    # insert data
    server.succeed("echo 'foo' > /shallow/foo/hello.txt")

    # backup
    server.succeed("systemctl start --wait sanoid")
    desktop.succeed("systemctl start --wait syncoid-pull-backup-mybackup")

    # destroy
    server.succeed("test -f /shallow/foo/hello.txt")
    server.succeed("zfs destroy -r spool/foo")
    server.fail("test -f /shallow/foo/hello.txt")

    # insert to shallow dataset
    server.succeed("echo 'shallow' > /shallow/foo/hello.txt")

    # restore
    server.succeed("ezfs-prepare-restore-pull-backup-mybackup")
    desktop.succeed("ezfs-restore-pull-backup-mybackup")

    # setup
    server.succeed("systemctl start --wait ezfs-setup-myfoo")

    # assert
    server.succeed("test -f /shallow/foo/hello.txt")
    server.succeed("cat /shallow/foo/hello.txt | grep '^foo$'")

    # unmount foo and check shallow dataset
    server.succeed("zfs unmount spool/foo")
    server.succeed("cat /shallow/foo/hello.txt | grep '^shallow$'")

    # unmount shallow and check non-zfs hello.txt
    server.succeed("zfs unmount spool/shallow");
    server.succeed("cat /shallow/foo/hello.txt | grep '^not zfs$'")
  '';
}
