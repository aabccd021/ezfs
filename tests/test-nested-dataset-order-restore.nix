inputs: {
  name = "nested-dataset-order-restore";

  nodes = import ./nodes-nested-dataset.nix inputs;

  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")
    desktop.wait_for_unit("multi-user.target")

    # Create pools
    server.succeed("zpool create spool /dev/vdb")
    desktop.succeed("zpool create dpool /dev/vdb")

    # Write to rootfs layer
    server.succeed("test ! -e /data/child/test.txt")
    server.succeed("mkdir -p /data/child")
    server.succeed("echo 'rootfs' > /data/child/test.txt")

    # Create datasets and mount (both setup services needed for zfs allow)
    server.succeed("ezfs-create-parent")
    server.succeed("ezfs-create-child")
    server.succeed("systemctl start --wait ezfs-mount")
    server.succeed("systemctl start --wait ezfs-mount")

    # Write to parent layer
    server.succeed("zfs unmount spool/parent/child")
    server.succeed("test ! -e /data/child/test.txt")
    server.succeed("mkdir -p /data/child")
    server.succeed("echo 'parent' > /data/child/test.txt")

    # Write to child layer
    server.succeed("zfs mount spool/parent/child")
    server.succeed("test ! -e /data/child/test.txt")
    server.succeed("mkdir -p /data/child")
    server.succeed("echo 'child' > /data/child/test.txt")

    # Backup both datasets
    server.succeed("systemctl start --wait sanoid")
    desktop.succeed("systemctl start --wait syncoid-pull-backup-mybackup-parent")
    desktop.succeed("systemctl start --wait syncoid-pull-backup-mybackup-child")

    # Destroy parent with snapshots (this also destroys child since it's a ZFS child)
    server.succeed("zfs destroy -r spool/parent")

    # Restore both datasets from backup
    server.succeed("ezfs-prepare-restore-pull-backup-mybackup-parent")
    server.succeed("ezfs-prepare-restore-pull-backup-mybackup-child")
    desktop.succeed("ezfs-restore-pull-backup-mybackup-parent")
    desktop.succeed("ezfs-restore-pull-backup-mybackup-child")

    # Mount via ezfs service (child first to simulate race condition)
    server.succeed("systemctl start --wait ezfs-mount")
    server.succeed("systemctl start --wait ezfs-mount")

    # Assert layered content after restore
    server.succeed("cat /data/child/test.txt | grep '^child$'")
    server.succeed("zfs unmount spool/parent/child")
    server.succeed("cat /data/child/test.txt | grep '^parent$'")
    server.succeed("zfs unmount spool/parent")
    server.succeed("cat /data/child/test.txt | grep '^rootfs$'")
  '';
}
