{
  pkgs,
  inputs,
}:

pkgs.testers.runNixOSTest {
  name = "test01";

  nodes.main = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
    ];
  };

  nodes.backup = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
    ];
  };

  testScript = '''';
}
