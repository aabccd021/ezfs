{
  pkgs,
  inputs,
  mockSecrets,
}:

pkgs.testers.runNixOSTest {
  name = "reboot-all";

  nodes = import ./pull-nodes.nix {
    inputs = inputs;
    mockSecrets = mockSecrets;
  };

  testScript = ''
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

    # insert data
    server.succeed("echo 'hello world' > /spool/foo/hello.txt")

    # backup
    server.succeed("systemctl start --wait sanoid")
    desktop.succeed("systemctl start --wait syncoid-pull-backup-mybackup")

    # reboot
    server.reboot()
    desktop.reboot()
    server.wait_for_unit("multi-user.target")
    desktop.wait_for_unit("multi-user.target")

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
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("cat /spool/foo/hello.txt | grep '^hello world$'")
  '';
}
