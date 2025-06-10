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
  test-simple-encrypted = mkTest ./simple-encrypted.nix;
  test-reboot-after-create = mkTest ./reboot-after-create.nix;
  test-reboot-after-restore = mkTest ./reboot-after-restore.nix;
}
