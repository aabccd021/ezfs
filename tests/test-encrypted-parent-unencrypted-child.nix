inputs:
let
  mock-secrets = inputs.mock-secrets-nix.lib.secrets;
in
{
  name = "encrypted-parent-unencrypted-child";

  nodes.server = {
    imports = [
      inputs.agenix.nixosModules.default
      inputs.ezfs.nixosModules.default
      inputs.age-mock-nix.nixosModules.default
    ];

    networking.hostId = "9b037621";
    virtualisation.emptyDiskImages = [ 4096 ];
    age.identityPaths = [ ];

    # Encrypted dataset at /data (ZFS sibling, not parent)
    ezfs.datasets.encrypted = {
      name = "spool/encrypted";
      hostId = "9b037621";
      options = {
        mountpoint = "/data";
        encryption = "on";
        keyformat = "passphrase";
        keylocation = "file:///run/encryption_key.txt";
      };
    };

    # Non-encrypted dataset at /data/child (ZFS sibling with nested mountpoint)
    ezfs.datasets.unencrypted = {
      name = "spool/unencrypted";
      hostId = "9b037621";
      options.mountpoint = "/data/child";
    };

    boot.initrd.postDeviceCommands = ''
      echo "encryption key" > /run/encryption_key.txt
      chmod 400 /run/encryption_key.txt
    '';

    systemd.services."zfs-import-spool".serviceConfig.TimeoutStartSec = "1s";
  };

  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")

    # Create pool and datasets
    server.succeed("zpool create spool /dev/vdb")
    server.succeed("ezfs-create-encrypted")
    server.succeed("ezfs-create-unencrypted")

    # Start only unencrypted service
    # zfs mount -a will skip encrypted (no key), but should NOT mount unencrypted
    # because its mountpoint /data/child requires /data to exist as a ZFS mount
    server.succeed("systemctl start --wait ezfs-setup-dataset-unencrypted")

    # Both should be mounted (encrypted mounted first by our logic)
    server.succeed("mountpoint /data")
    server.succeed("mountpoint /data/child")

    # Verify they are ZFS mounts
    server.succeed("zfs list spool/encrypted")
    server.succeed("zfs list spool/unencrypted")

    # Write test files
    server.succeed("echo 'encrypted' > /data/test.txt")
    server.succeed("echo 'unencrypted' > /data/child/test.txt")

    # Verify files are on correct datasets
    server.succeed("zfs unmount spool/unencrypted")
    server.succeed("test -f /data/test.txt")
    server.fail("test -f /data/child/test.txt")

    print("Test passed: encrypted parent mountpoint, non-encrypted child mountpoint works")
  '';
}
