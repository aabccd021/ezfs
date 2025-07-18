inputs:

{
  name = "pull-states-reboot-all";

  nodes = import ./nodes-pull-states.nix inputs;

  testScript = ''
    def assert_server():
        server.succeed("zfs get -H -o value compression spool/foo | grep '^zstd$'")
        server.succeed("zfs get -H -o value setuid spool/foo | grep '^off$'")
        server.succeed("zfs get -H -o value exec spool/foo | grep '^off$'")
        server.succeed("zfs get -H -o value devices spool/foo | grep '^off$'")
        server.succeed("stat -c '%U:%G' /spool/foo | grep '^myserveruser:myservergroup$'")
        assert server.succeed("zfs allow spool") == "", "zfs allow spool should be empty"
        server.succeed("zfs allow spool/foo | grep -q 'user mybackupuser bookmark,hold,send'")

    server.start(allow_reboot=True)
    desktop.start(allow_reboot=True)

    # create
    server.wait_for_unit("multi-user.target")
    server.succeed("zpool create spool /dev/vdb")
    server.succeed("ezfs-create-myfoo")
    desktop.succeed("zpool create dpool /dev/vdb")

    # reboot
    server.reboot()
    desktop.reboot()
    server.wait_for_unit("multi-user.target")
    desktop.wait_for_unit("multi-user.target")
    assert_server()

    # insert data
    server.succeed("echo 'hello world' > /spool/foo/hello.txt")

    # backup
    server.succeed("systemctl start --wait sanoid")
    desktop.succeed("systemctl start --wait syncoid-pull-backup-mybackup")

    # assert permissions
    canmount = desktop.succeed("zfs get -H -o value canmount dpool/foo_backup")
    assert canmount == "off\n", "Unexpected canmount value: " + canmount
    mountpoint = desktop.succeed("zfs get -H -o value mountpoint dpool/foo_backup")
    assert mountpoint == "none\n", "Unexpected mountpoint value: " + mountpoint
    keylocation = desktop.succeed("zfs get -H -o value keylocation dpool/foo_backup")
    assert keylocation == "file:///dev/null\n", "Unexpected keylocation value: " + keylocation

    # reboot
    server.reboot()
    desktop.reboot()
    server.wait_for_unit("multi-user.target")
    desktop.wait_for_unit("multi-user.target")
    assert_server()

    # destroy
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("zfs destroy -r spool/foo")
    server.fail("test -f /spool/foo/hello.txt")

    # reboot
    server.reboot()
    desktop.reboot()
    server.wait_for_unit("multi-user.target")
    desktop.wait_for_unit("multi-user.target")

    # restore
    server.succeed("ezfs-prepare-restore-pull-backup-mybackup")
    desktop.succeed("ezfs-restore-pull-backup-mybackup")

    # reboot
    server.reboot()
    server.wait_for_unit("multi-user.target")

    # assert
    assert_server()
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("cat /spool/foo/hello.txt | grep '^hello world$'")
  '';
}
