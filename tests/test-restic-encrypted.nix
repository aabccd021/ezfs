inputs:
let
  mock-secrets = inputs.mock-secrets-nix.lib.secrets;
  sharedModule =
    { config, ... }:
    {
      ezfs.datasets.myfoo = {
        name = "spool/foo";
        hostId = "9b037621";
        user = "myserveruser";
        group = "myservergroup";
        options = {
          compression = "zstd";
          mountpoint = "/spool/foo";
          encryption = "on";
          keyformat = "passphrase";
          keylocation = "file:///run/encryption_key.txt";
        };
      };

      ezfs.restic-backups.myrestic = {
        sourceDatasetId = "myfoo";
        repository = "s3:http://localhost:3900/test-bucket";
        passwordFile = config.age-mock.secrets.restic_password.file;
        awsAccessKeyIdFile = config.age-mock.secrets.aws_access_key.file;
        awsSecretAccessKeyFile = config.age-mock.secrets.aws_secret_key.file;
      };

      # required for test only
      virtualisation.emptyDiskImages = [ 4096 ]; # add /dev/vdb
      age.identityPaths = [ config.age-mock.identityPath ];
      imports = [ inputs.age-mock-nix.nixosModules.default ];
    };
in

{
  name = "restic-encrypted";

  nodes.server =
    { pkgs, lib, ... }:
    {
      imports = [
        inputs.agenix.nixosModules.default
        inputs.ezfs.nixosModules.default
        sharedModule
      ];

      ezfs.enable = true;
      networking.hostId = "9b037621";

      ezfs.restic-backups.myrestic.enable = true;

      users.users.myserveruser.isNormalUser = true;
      users.groups.myservergroup = { };

      # Garage S3 server
      services.garage = {
        enable = true;
        package = pkgs.garage;
        settings = {
          replication_factor = 1;
          db_engine = "sqlite";
          metadata_dir = "/var/lib/garage/meta";
          data_dir = "/var/lib/garage/data";
          s3_api = {
            api_bind_addr = "[::]:3900";
            s3_region = "garage";
            root_domain = ".s3.garage";
          };
          rpc_bind_addr = "[::]:3901";
          rpc_secret = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
        };
      };

      # Required for test only
      systemd.services."zfs-import-spool".serviceConfig.TimeoutStartSec = "1s";
      age-mock = {
        enable = true;
        secrets.restic_password.value = "test-restic-password-123";
        # These will be updated dynamically in test script after Garage setup
        secrets.aws_access_key.value = "placeholder";
        secrets.aws_secret_key.value = "placeholder";
      };

      environment.systemPackages = [ pkgs.restic ];
    };

  testScript =
    { nodes, ... }:
    ''
      start_all()
      server.wait_for_unit("multi-user.target")

      # Wait for Garage to be ready
      server.wait_for_unit("garage.service")
      server.wait_for_open_port(3900)
      server.wait_for_open_port(3901)

      # Get Garage node ID and configure cluster
      node_id = server.succeed("garage node id -q 2>/dev/null || garage node id 2>/dev/null | head -1").strip()
      server.succeed(f"garage layout assign -z dc1 -c 1G {node_id}")
      server.succeed("garage layout apply --version 1")

      # Create bucket
      server.succeed("garage bucket create test-bucket")

      # Create API key and get credentials
      key_output = server.succeed("garage key create restic-key")

      # Parse the key output to get access key and secret key
      access_key = ""
      secret_key = ""
      for line in key_output.split("\n"):
          if "Key ID:" in line:
              access_key = line.split("Key ID:")[1].strip()
          elif "Secret key:" in line:
              secret_key = line.split("Secret key:")[1].strip()

      # Grant permissions to bucket
      server.succeed("garage bucket allow --read --write --owner test-bucket --key restic-key")

      # Update the agenix secret files with actual credentials
      server.succeed(f"echo -n '{access_key}' > ${nodes.server.age.secrets.ezfs_restic_aws_access_key_myrestic.path}")
      server.succeed(f"echo -n '{secret_key}' > ${nodes.server.age.secrets.ezfs_restic_aws_secret_key_myrestic.path}")

      # Create zpool and encryption key
      server.succeed("zpool create spool /dev/vdb")
      server.succeed("echo 'encryption key' > /run/encryption_key.txt")
      server.succeed("chmod 400 /run/encryption_key.txt")
      server.succeed("ezfs-create-myfoo")
      server.succeed("systemctl start --wait ezfs-mount")

      # Verify initial setup
      server.succeed("stat -c '%U:%G' /spool/foo | grep '^myserveruser:myservergroup$'")

      # Insert data
      server.succeed("echo 'hello restic encrypted' > /spool/foo/hello.txt")
      server.succeed("chown myserveruser:myservergroup /spool/foo/hello.txt")

      # Create snapshot with sanoid
      server.succeed("systemctl start --wait sanoid")

      # Verify snapshot exists
      server.succeed("zfs list -t snapshot spool/foo | grep autosnap")

      # Run restic backup
      server.succeed("systemctl start --wait ${nodes.server.ezfs.restic-backups.myrestic.backupService}")

      # Simulate data loss
      server.succeed("test -f /spool/foo/hello.txt")
      server.succeed("zfs destroy -r spool/foo")
      server.fail("test -f /spool/foo/hello.txt")

      # Restore: first prepare (recreate dataset)
      server.succeed("echo 'encryption key' > /run/encryption_key.txt")
      server.succeed("chmod 400 /run/encryption_key.txt")
      server.succeed("ezfs-prepare-restore-restic-backup-myrestic")

      # Restore: run restic restore
      server.succeed("ezfs-restore-restic-backup-myrestic")

      # Setup dataset after restore
      server.succeed("systemctl start --wait ezfs-mount")

      # Verify data restored
      server.succeed("test -f /spool/foo/hello.txt")
      server.succeed("cat /spool/foo/hello.txt | grep '^hello restic encrypted$'")
      server.succeed("stat -c '%U:%G' /spool/foo | grep '^myserveruser:myservergroup$'")
    '';
}
