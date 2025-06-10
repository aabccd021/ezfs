{
  pkgs,
  inputs,
  mockSecrets,
}:
let
  mkTest =
    nixFile:
    import nixFile {
      pkgs = pkgs;
      inputs = inputs;
      mockSecrets = mockSecrets;
    };
in
{
  test01 = mkTest ./test01.nix;
  simple-encrypted = mkTest ./simple-encrypted.nix;
}
