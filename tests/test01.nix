{
  pkgs,
}:

pkgs.testers.runNixOSTest {
  name = "integration-start";

  nodes.main.imports = {
    imports = [
      ../nixosModules/default.nix
    ];
  };

  nodes.backup.imports = {
    imports = [
      ../nixosModules/default.nix
    ];
  };

  testScript = ''
    start_all()

    main.wait_for_unit("multi-user.target")
  '';
}
