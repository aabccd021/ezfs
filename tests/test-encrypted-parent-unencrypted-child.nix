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

    # Mount both datasets
    server.succeed("systemctl start --wait ezfs-mount")

    # Write to unencrypted layer
    server.succeed("echo 'unencrypted' > /data/child/test.txt")

    # Unmount unencrypted, write to encrypted layer
    server.succeed("zfs unmount spool/unencrypted")
    server.succeed("echo 'encrypted' > /data/child/test.txt")

    # Unmount encrypted, write to rootfs layer
    server.succeed("zfs unmount spool/encrypted")
    server.succeed("mkdir -p /data/child")
    server.succeed("echo 'rootfs' > /data/child/test.txt")

    # Remount via service
    server.succeed("systemctl start --wait ezfs-mount")

    # Assert layers are correct
    server.succeed("cat /data/child/test.txt | grep '^unencrypted$'")
    server.succeed("zfs unmount spool/unencrypted")
    server.succeed("cat /data/child/test.txt | grep '^encrypted$'")
    server.succeed("zfs unmount spool/encrypted")
    server.succeed("cat /data/child/test.txt | grep '^rootfs$'")
  '';
}
