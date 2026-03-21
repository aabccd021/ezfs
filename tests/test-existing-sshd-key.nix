inputs:
let
  mock-secrets = inputs.mock-secrets-nix.lib.secrets;

  # Shared ezfs configuration - same as nodes-pull-basic.nix
  sharedModule =
    { config, lib, ... }:
    {
      ezfs = {
        hosts = {
          "9b037621" = {
            publicKey = mock-secrets.ed25519.bob.public;
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
        pull-backups.mybackup = {
          targetDatasetName = "dpool/foo_backup";
          sourceDatasetId = "myfoo";
          host = "server";
          user = "mybackupuser";
          publicKey = mock-secrets.ed25519.alice.public;
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

{
  name = "existing-sshd-key";

  # Server is the SOURCE of the backup - ezfs adds sshd key here
  # We also add an existing ed25519 key to test the conflict
  nodes.server =
    { config, lib, ... }:
    {
      imports = [
        inputs.sops-nix.nixosModules.default
        inputs.ezfs.nixosModules.default
        sharedModule
      ];

      networking.hostId = "9b037621";

      systemd.services."zfs-import-spool".serviceConfig.TimeoutStartSec = "1s";

      sops-mock = {
        enable = true;
        secrets.sshd_private_key.value = mock-secrets.ed25519.bob.private;
        secrets.sshd_private_key.key = "sshd_private_key";
      };

      boot.initrd.postDeviceCommands = ''
        echo "encryption key" > /run/encryption_key.txt
        chmod 400 /run/encryption_key.txt
      '';

      # Add an existing ed25519 key BEFORE ezfs adds its key
      services.openssh.hostKeys = lib.mkBefore [
        {
          type = "ed25519";
          path = "/etc/ssh/ssh_host_ed25519_key";
        }
      ];
    };

  # Desktop is the TARGET of the backup - enables the pull-backup
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
      secrets.backup_private_key.value = mock-secrets.ed25519.alice.private;
      secrets.backup_private_key.key = "backup_ssh_key";
    };
  };

  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")
    desktop.wait_for_unit("multi-user.target")

    # Check what SSH host keys exist on the server
    print("=== SSH host keys on server ===")
    print(server.succeed("ls -la /etc/ssh/"))

    # Check sshd config
    print("=== sshd_config HostKey entries ===")
    print(server.succeed("grep '^HostKey' /etc/ssh/sshd_config || echo 'No HostKey entries'"))

    # Check if both keys exist
    server.succeed("test -f /etc/ssh/ssh_host_ed25519_key")
    print("User ed25519 key exists: /etc/ssh/ssh_host_ed25519_key")

    has_ezfs_key = server.succeed("test -f /run/secrets/ezfs_sshd_key && echo yes || echo no").strip()
    print("ezfs sshd key exists: " + has_ezfs_key)

    if has_ezfs_key == "yes":
        # Get fingerprints
        fp_user = server.succeed("ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key").strip()
        fp_ezfs = server.succeed("ssh-keygen -lf /run/secrets/ezfs_sshd_key").strip()
        print("User key: " + fp_user)
        print("ezfs key: " + fp_ezfs)

        # Check which key sshd presents
        presented = server.succeed("ssh-keyscan -t ed25519 localhost 2>/dev/null").strip()
        print("Key presented by sshd: " + presented)

        # Now test if backup actually works with both keys configured
        print("=== Testing if backup works ===")
        server.succeed("zpool create spool /dev/vdb")
        server.succeed("ezfs-create-myfoo")
        desktop.succeed("zpool create dpool /dev/vdb")
        server.succeed("systemctl start --wait ezfs-setup-dataset-myfoo")
        server.succeed("echo 'test' > /spool/foo/test.txt")
        server.succeed("zfs snapshot spool/foo@test")

        # This should use the ezfs key - will it work with duplicate keys?
        result = desktop.execute("systemctl start --wait syncoid-pull-backup-mybackup 2>&1")
        print("Backup result: exit code " + str(result[0]))
        if result[0] != 0:
            print("Backup FAILED as expected - SSH presents wrong key to client")
            print("This confirms: duplicate ed25519 SSH host keys break ezfs backups")
            print("The ezfs assertion should prevent this configuration")
        else:
            # If backup succeeds, that's unexpected - fail the test
            raise Exception("Backup succeeded despite duplicate keys - this should not happen")
    else:
        raise Exception("ezfs sshd key was NOT added - test configuration error")
  '';
}
