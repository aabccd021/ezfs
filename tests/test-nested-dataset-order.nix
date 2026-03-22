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
  };

  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")

    # Create pool and datasets
    server.succeed("zpool create spool /dev/vdb")
    server.succeed("ezfs-create-parent")
    server.succeed("ezfs-create-child")

    # Start only child service - parent should be mounted first via dependsOn
    server.succeed("systemctl start --wait ezfs-setup-dataset-child")

    # Verify both datasets are mounted
    server.succeed("mountpoint /data")
    server.succeed("mountpoint /data/child")

    # Write test files
    server.succeed("echo 'parent' > /data/test.txt")
    server.succeed("echo 'child' > /data/child/test.txt")

    # Verify files are on correct datasets
    server.succeed("zfs unmount spool/parent/child")
    server.succeed("test -f /data/test.txt")
    server.fail("test -f /data/child/test.txt")
  '';
}
