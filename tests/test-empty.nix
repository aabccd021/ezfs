inputs: {
  name = "empty";

  nodes.main = {
    imports = [
      inputs.agenix.nixosModules.default
      inputs.ezfs.nixosModules.default
    ];
  };

  testScript = "";
}
