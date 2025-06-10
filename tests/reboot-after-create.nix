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
      datasets."zpool/foo" = {
        options = {
          encryption = "on";
          keyformat = "passphrase";
        };
        pull-backup.mybackup = {
          host = "server.com";
          user = "mybackupuser";
          publicKey = builtins.readFile mockSecrets.ed25519.alice.public;
          privateKey = {
            key = "name_of_key";
            # In this test, this sopsFile will be overriden by sops-mock,
            # but in production you need to provide a real sops file.
            sopsFile = ../secrets.yaml;
          };
        };
      };
    };

    # required for test only
    virtualisation.emptyDiskImages = [ 4096 ]; # add /dev/vdb
    sops.validateSopsFiles = false; # Required for allow-import-from-derivation = false;
  };
in

pkgs.testers.runNixOSTest {
  name = "reboot-after-create";

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
      datasets."zpool/foo".hourly = 1;
    };

    ezfs.datasets."zpool/foo" = {
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

    # simulate putting secrets
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

      # Required for test only
      inputs.sops-nix-mock.nixosModules.default
    ];

    networking.hostId = "76219b03";

    ezfs.datasets."zpool/foo".pull-backup.mybackup = {
      enable = true;
      targetDataset = "backup_zpool/foo_backup";
    };

    # Required for test only
    sops-mock = {
      enable = true;
      secrets.ezfs_pull_backup_zpool_foo = builtins.readFile mockSecrets.ed25519.alice.private;
    };
  };

  testScript = ''
    server.start(allow_reboot=True)
    desktop.start()

    # create
    server.wait_for_unit("multi-user.target")
    server.succeed("zpool create zpool /dev/vdb")
    server.succeed("ezfs-create-zpool-foo")
    desktop.succeed("zpool create backup_zpool /dev/vdb")

    # reboot
    server.reboot()
    server.wait_for_unit("multi-user.target")

    # insert data
    server.succeed("echo 'hello world' > /zpool/foo/hello.txt")

    # backup
    server.succeed("systemctl start --wait sanoid")
    desktop.succeed("systemctl start --wait syncoid-pull-backup-zpool-foo")

    # destroy
    server.succeed("test -f /zpool/foo/hello.txt")
    server.succeed("zfs destroy -r zpool/foo")
    server.fail("test -f /zpool/foo/hello.txt")

    # restore
    server.succeed("ezfs-prepare-pull-restore-zpool-foo")
    desktop.succeed("syncoid-pull-restore-zpool-foo")
    server.succeed("systemctl start --wait ezfs-setup-zpool-foo")

    # assert
    server.succeed("test -f /zpool/foo/hello.txt")
    server.succeed("cat /zpool/foo/hello.txt | grep '^hello world$'")
  '';
}
