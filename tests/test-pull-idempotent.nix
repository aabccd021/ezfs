{
  pkgs,
  inputs,
  mockSecrets,
  ...
}:

pkgs.testers.runNixOSTest {
  name = "idempotent";

  nodes = import ./nodes-pull-basic.nix {
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

    # setup
    server.succeed("systemctl start --wait ezfs-setup-dataset-myfoo")

    # insert data
    server.succeed("echo 'hello world' > /spool/foo/hello.txt")
    server.succeed("systemctl start --wait ezfs-setup-dataset-myfoo")

    # backup
    server.succeed("systemctl start --wait sanoid")
    desktop.succeed("systemctl start --wait syncoid-pull-backup-mybackup")
    server.succeed("systemctl start --wait ezfs-setup-dataset-myfoo")

    # destroy
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("zfs destroy -r spool/foo")
    server.fail("test -f /spool/foo/hello.txt")

    # restore
    server.succeed("ezfs-prepare-restore-pull-backup-mybackup")
    desktop.succeed("ezfs-restore-pull-backup-mybackup")

    # setup
    server.succeed("systemctl start --wait ezfs-setup-dataset-myfoo")

    # assert
    server.succeed("test -f /spool/foo/hello.txt")
    server.succeed("cat /spool/foo/hello.txt | grep '^hello world$'")
    server.succeed("systemctl start --wait ezfs-setup-dataset-myfoo")
  '';
}
