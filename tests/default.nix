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
  test-empty = mkTest ./empty.nix;
  test-enc-key-from-module-config = mkTest ./enc-key-from-module-config.nix;
  test-idempotent = mkTest ./idempotent.nix;
  test-multi-dataset-no-reboot = mkTest ./multi-dataset-no-reboot.nix;
  test-reboot-after-backup = mkTest ./reboot-after-backup.nix;
  test-reboot-after-create = mkTest ./reboot-after-create.nix;
  test-reboot-after-destroy = mkTest ./reboot-after-destroy.nix;
  test-reboot-after-restore = mkTest ./reboot-after-restore.nix;
  test-reboot-all = mkTest ./reboot-all.nix;
  test-reboot-all-canmount-noauto = mkTest ./reboot-all-canmount-noauto.nix;
  test-reboot-all-canmount-on = mkTest ./reboot-all-canmount-on.nix;
  test-reboot-all-multi-dataset = mkTest ./reboot-all-multi-dataset.nix;
  test-simple-encrypted = mkTest ./simple-encrypted.nix;
}
