{
  pkgs,
  inputs,
  mockSecrets,
  ...
}:
let
  sharedModule = {
    boot.supportedFilesystems = [ "zfs" ];

    ezfs = {
      sshdPublicKey = builtins.readFile mockSecrets.ed25519.bob.public;
      datasets."spool/shallow" = {
        options = {
          mountpoint = "/shallow";
        };
      };
      datasets."spool/foo" = {
        dependsOn = [ "spool/shallow" ];
        options = {
          encryption = "on";
          keyformat = "passphrase";
          mountpoint = "/shallow/foo";
        };
        pull-backup.mybackup = {
          host = "server.com";
          user = "mybackupuser";
          publicKey = builtins.readFile mockSecrets.ed25519.alice.public;
          privateKeySopsName = "ezfs_private_key";
          privateKey = {
            key = "name_of_key";
            sopsFile = ../secrets.yaml;
          };
        };
      };
    };

    virtualisation.emptyDiskImages = [ 4096 ];
    sops.validateSopsFiles = false;
  };
in

pkgs.testers.runNixOSTest {
  name = "reboot-all-multi-dataset";

  nodes.server = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
      sharedModule
    ];

    networking = {
      hostId = "9b037621";
      domain = "com";
    };

    services.sanoid = {
      enable = true;
      datasets."spool/foo".hourly = 1;
    };

    ezfs.datasets."spool/foo" = {
      enable = true;
      options.keylocation = "file:///run/encryption_key.txt";
    };

    ezfs.datasets."spool/shallow".enable = true;

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
      cp -Lr ${mockSecrets.ed25519.bob.private} /run/sshd_host_key
      chmod -R 400 /run/sshd_host_key
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

    ezfs.datasets."spool/foo".pull-backup.mybackup = {
      enable = true;
      targetDataset = "dpool/foo_backup";
    };

    systemd.services."zfs-import-dpool".serviceConfig.TimeoutStartSec = "1s";

    sops-mock = {
      enable = true;
      secrets.ezfs_private_key = builtins.readFile mockSecrets.ed25519.alice.private;
    };
  };

  testScript = ''
    server.start(allow_reboot=True)
    desktop.start(allow_reboot=True)

    # create hello before mounting anything
    server.wait_for_unit("multi-user.target")
    server.succeed("mkdir -p /shallow/foo")
    server.succeed("echo 'not zfs' > /shallow/foo/hello.txt")

    # create
    server.succeed("zpool create spool /dev/vdb")
    server.succeed("ezfs-create-spool-foo")
    server.succeed("ezfs-create-spool-shallow")
    desktop.succeed("zpool create dpool /dev/vdb")

    # reboot
    server.reboot()
    desktop.reboot()
    server.wait_for_unit("multi-user.target")
    desktop.wait_for_unit("multi-user.target")

    # insert data
    server.succeed("echo 'foo' > /shallow/foo/hello.txt")

    # backup
    server.succeed("systemctl start --wait sanoid")
    desktop.succeed("systemctl start --wait syncoid-pull-backup-spool-foo")

    # reboot
    server.reboot()
    desktop.reboot()
    server.wait_for_unit("multi-user.target")
    desktop.wait_for_unit("multi-user.target")

    # destroy
    server.succeed("test -f /shallow/foo/hello.txt")
    server.succeed("zfs destroy -r spool/foo")
    server.fail("test -f /shallow/foo/hello.txt")

    # insert to shallow dataset
    server.succeed("echo 'shallow' > /shallow/foo/hello.txt")

    # reboot
    server.reboot()
    desktop.reboot()
    server.wait_for_unit("multi-user.target")
    desktop.wait_for_unit("multi-user.target")

    # restore
    server.succeed("ezfs-prepare-pull-restore-spool-foo")
    desktop.succeed("syncoid-pull-restore-spool-foo")

    # reboot
    server.reboot()
    server.wait_for_unit("multi-user.target")

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
