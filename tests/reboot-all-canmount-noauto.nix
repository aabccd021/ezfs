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
      datasets."spool/foo" = {
        options = {
          encryption = "on";
          keyformat = "passphrase";
          canmount = "noauto";
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
  name = "reboot-all-canmount-noauto";

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

    services.openssh = {
      enable = true;
      hostKeys = [
        {
          path = "/run/sshd_host_key";
          type = "ed25519";
        }
      ];
    };

    boot.initrd.postDeviceCommands = ''
      echo "encryption key" > /run/encryption_key.txt
      cp -Lr ${mockSecrets.ed25519.bob.private} /run/sshd_host_key
      chmod -R 400 /run/sshd_host_key
    '';

    systemd.services."zfs-import-spool".serviceConfig.TimeoutStartSec = "1s";

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

    # create
    server.wait_for_unit("multi-user.target")
    server.succeed("zpool create spool /dev/vdb")
    server.succeed("ezfs-create-spool-foo")
    desktop.succeed("zpool create dpool /dev/vdb")

    # reboot
    server.reboot()
    desktop.reboot()
    server.wait_for_unit("multi-user.target")
    desktop.wait_for_unit("multi-user.target")

    # insert data
    server.succeed("echo 'hello world' > /spool/foo/hello.txt")

    # backup
    server.succeed("systemctl start --wait sanoid")
    desktop.succeed("systemctl start --wait syncoid-pull-backup-spool-foo")

    # reboot
    server.reboot()
    desktop.reboot()
    server.wait_for_unit("multi-user.target")
    desktop.wait_for_unit("multi-user.target")

    # destroy
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("zfs destroy -r spool/foo")
    server.fail("test -f /spool/foo/hello.txt")

    # reboot
    server.reboot()
    desktop.reboot()
    server.wait_for_unit("multi-user.target")
    desktop.wait_for_unit("multi-user.target")

    # restore
    server.succeed("ezfs-prepare-pull-restore-spool-foo")
    desktop.succeed("ezfs-restore-spool-foo")

    # reboot
    server.reboot()
    server.wait_for_unit("multi-user.target")

    # assert
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("cat /spool/foo/hello.txt | grep '^hello world$'")
  '';
}
