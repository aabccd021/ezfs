inputs:
let
  mock-secrets = inputs.mock-secrets-nix.lib.secrets;
in
{
  name = "encrypted-parent-no-key";

  nodes.server = {
    imports = [
      inputs.agenix.nixosModules.default
      inputs.ezfs.nixosModules.default
      inputs.age-mock-nix.nixosModules.default
    ];

    networking.hostId = "9b037621";
    virtualisation.emptyDiskImages = [ 4096 ];
    age.identityPaths = [ ];

    # Encrypted dataset at /data - key NOT available during zfs mount -a
    ezfs.datasets.encrypted = {
      name = "spool/encrypted";
      hostId = "9b037621";
      options = {
        mountpoint = "/data";
        encryption = "on";
        keyformat = "passphrase";
        # Key file that doesn't exist during zfs mount -a
        keylocation = "file:///run/late_encryption_key.txt";
      };
    };

    # Non-encrypted dataset at /data/child
    ezfs.datasets.unencrypted = {
      name = "spool/unencrypted";
      hostId = "9b037621";
      options.mountpoint = "/data/child";
      dependsOn = [ "encrypted" ];
    };

    systemd.services."zfs-import-spool".serviceConfig.TimeoutStartSec = "1s";
  };

  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")

    # Create pool and datasets
    server.succeed("zpool create spool /dev/vdb")

    # Create key file ONLY for dataset creation
    server.succeed("echo 'encryption key' > /run/late_encryption_key.txt")
    server.succeed("chmod 400 /run/late_encryption_key.txt")
    server.succeed("ezfs-create-encrypted")
    server.succeed("ezfs-create-unencrypted")

    # Unload the key and remove the file to simulate it not being available
    server.succeed("zfs unload-key spool/encrypted")
    server.succeed("rm /run/late_encryption_key.txt")

    # With dependsOn, the unencrypted service requires encrypted to succeed first.
    # Since encrypted cannot load its key, it fails, and unencrypted also fails.
    # This is CORRECT behavior - it prevents the data leak scenario!
    server.fail("systemctl start --wait ezfs-setup-dataset-unencrypted")

    # Neither dataset should be mounted - both services failed
    server.fail("mountpoint /data")
    server.fail("mountpoint /data/child")

    print("Test passed: dependsOn correctly prevents mounting child when encrypted parent is unavailable")
  '';
}
