{
  pkgs,
  inputs,
  mockSecrets,
  ...
}:

pkgs.testers.runNixOSTest {
  name = "multi-dataset-no-reboot";

  nodes = import ./nodes-pull-multi-dataset.nix {
    inputs = inputs;
    mockSecrets = mockSecrets;
  };

  testScript = ''
    start_all()

    # create hello before mounting anything
    server.wait_for_unit("multi-user.target")
    server.succeed("mkdir -p /shallow/foo")
    server.succeed("echo 'not zfs' > /shallow/foo/hello.txt")

    # create
    server.succeed("zpool create spool /dev/vdb")
    server.succeed("ezfs-create-myfoo")
    server.succeed("ezfs-create-myshallow")
    desktop.succeed("zpool create dpool /dev/vdb")

    # setup
    server.succeed("systemctl start --wait ezfs-setup-myfoo")

    # insert data
    server.succeed("echo 'foo' > /shallow/foo/hello.txt")

    # backup
    server.succeed("systemctl start --wait sanoid")
    desktop.succeed("systemctl start --wait syncoid-pull-backup-mybackup")

    # destroy
    server.succeed("test -f /shallow/foo/hello.txt")
    server.succeed("zfs destroy -r spool/foo")
    server.fail("test -f /shallow/foo/hello.txt")

    # insert to shallow dataset
    server.succeed("echo 'shallow' > /shallow/foo/hello.txt")

    # restore
    server.succeed("ezfs-prepare-restore-pull-backup-mybackup")
    desktop.succeed("ezfs-restore-pull-backup-mybackup")

    # setup
    server.succeed("systemctl start --wait ezfs-setup-myfoo")

    # assert
    server.succeed("test -f /shallow/foo/hello.txt")
    server.succeed("cat /shallow/foo/hello.txt | grep '^foo$'")

    # unmount foo and check shallow dataset
    server.succeed("zfs unmount spool/foo")
    server.succeed("cat /shallow/foo/hello.txt | grep '^shallow$'")

    # unmount shallow and check non-zfs hello.txt
    server.succeed("zfs unmount spool/shallow");
    server.succeed("cat /shallow/foo/hello.txt | grep '^not zfs$'")
  '';
}
