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
  test-empty = mkTest ./test-empty.nix;
  test-pull-enc-key-from-module-config = mkTest ./test-pull-enc-key-from-module-config.nix;
  test-pull-idempotent = mkTest ./test-pull-idempotent.nix;
  test-pull-multi-dataset-no-reboot = mkTest ./test-pull-multi-dataset-no-reboot.nix;
  test-pull-reboot-all = mkTest ./test-pull-reboot-all.nix;
  test-pull-reboot-all-multi-dataset = mkTest ./test-pull-reboot-all-multi-dataset.nix;
  test-pull-states-reboot-all = mkTest ./test-pull-states-reboot-all.nix;
  test-pull-states = mkTest ./test-pull-states.nix;
  test-pull-encrypted = mkTest ./test-pull-encrypted.nix;
  test-push-encrypted = mkTest ./test-push-encrypted.nix;
}
