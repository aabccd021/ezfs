inputs:
let
  mock-secrets = inputs.mock-secrets-nix.lib.secrets;
in
{
  name = "nested-dataset-order";

  nodes.server = {
    imports = [
      inputs.agenix.nixosModules.default
      inputs.ezfs.nixosModules.default
      inputs.age-mock-nix.nixosModules.default
    ];

    networking.hostId = "9b037621";
    virtualisation.emptyDiskImages = [ 4096 ];
    age.identityPaths = [ ];

    ezfs.datasets.parent = {
      name = "spool/parent";
      hostId = "9b037621";
      options.mountpoint = "/data";
    };

    ezfs.datasets.child = {
      name = "spool/parent/child";
      hostId = "9b037621";
      options.mountpoint = "/data/child";
    };

    systemd.services."zfs-import-spool".serviceConfig.TimeoutStartSec = "1s";

    # Force parent to run only after child succeeds
    systemd.services."ezfs-setup-dataset-parent" = {
      after = [ "ezfs-setup-dataset-child.service" ];
      requires = [ "ezfs-setup-dataset-child.service" ];
    };
  };

  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")

    # Create pool and datasets
    server.succeed("zpool create spool /dev/vdb")
    server.succeed("ezfs-create-parent")
    server.succeed("ezfs-create-child")

    # Mount both datasets
    server.succeed("systemctl start --wait ezfs-setup-dataset-child")

    # Write to child layer
    server.succeed("echo 'child' > /data/child/test.txt")

    # Unmount child, write to parent layer
    server.succeed("zfs unmount spool/parent/child")
    server.succeed("echo 'parent' > /data/child/test.txt")

    # Unmount parent, write to rootfs layer
    server.succeed("zfs unmount spool/parent")
    server.succeed("mkdir -p /data/child")
    server.succeed("echo 'rootfs' > /data/child/test.txt")

    # Remount via service
    server.succeed("systemctl start --wait ezfs-setup-dataset-child")

    # Assert layers are correct
    server.succeed("cat /data/child/test.txt | grep '^child$'")
    server.succeed("zfs unmount spool/parent/child")
    server.succeed("cat /data/child/test.txt | grep '^parent$'")
    server.succeed("zfs unmount spool/parent")
    server.succeed("cat /data/child/test.txt | grep '^rootfs$'")
  '';
}
