inputs: {
  name = "encrypted-parent-with-key-restore";

  nodes = import ./nodes-encrypted-parent-child.nix inputs;

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
    server.succeed("ezfs-create-encrypted")
    server.succeed("ezfs-create-unencrypted")
    server.succeed("systemctl start --wait ezfs-mount")
    server.succeed("systemctl start --wait ezfs-mount")

    # Write to encrypted layer
    server.succeed("zfs unmount spool/unencrypted")
    server.succeed("test ! -e /data/child/test.txt")
    server.succeed("mkdir -p /data/child")
    server.succeed("echo 'encrypted' > /data/child/test.txt")

    # Write to unencrypted layer
    server.succeed("zfs mount spool/unencrypted")
    server.succeed("test ! -e /data/child/test.txt")
    server.succeed("mkdir -p /data/child")
    server.succeed("echo 'unencrypted' > /data/child/test.txt")

    # Backup both datasets
    server.succeed("systemctl start --wait sanoid")
    desktop.succeed("systemctl start --wait syncoid-pull-backup-mybackup-encrypted")
    desktop.succeed("systemctl start --wait syncoid-pull-backup-mybackup-unencrypted")

    # Destroy both datasets (with snapshots created by sanoid)
    server.succeed("zfs destroy -r spool/unencrypted")
    server.succeed("zfs destroy -r spool/encrypted")

    # Restore both datasets from backup
    server.succeed("ezfs-prepare-restore-pull-backup-mybackup-encrypted")
    server.succeed("ezfs-prepare-restore-pull-backup-mybackup-unencrypted")
    desktop.succeed("ezfs-restore-pull-backup-mybackup-encrypted")
    desktop.succeed("ezfs-restore-pull-backup-mybackup-unencrypted")

    # Mount via ezfs service (child first to simulate race condition)
    server.succeed("systemctl start --wait ezfs-mount")
    server.succeed("systemctl start --wait ezfs-mount")

    # Assert layered content after restore
    server.succeed("cat /data/child/test.txt | grep '^unencrypted$'")
    server.succeed("zfs unmount spool/unencrypted")
    server.succeed("cat /data/child/test.txt | grep '^encrypted$'")
    server.succeed("zfs unmount spool/encrypted")
    server.succeed("cat /data/child/test.txt | grep '^rootfs$'")
  '';
}
