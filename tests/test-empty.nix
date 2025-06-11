{
  pkgs,
  inputs,
  ...
}:

pkgs.testers.runNixOSTest {
  name = "empty";

  nodes.main = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
    ];
  };

  testScript = "";
}
