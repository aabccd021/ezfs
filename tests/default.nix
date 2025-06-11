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
  test-pull-enc-key-from-module-config = mkTest ./pull-enc-key-from-module-config.nix;
  test-pull-idempotent = mkTest ./pull-idempotent.nix;
  test-pull-multi-dataset-no-reboot = mkTest ./pull-multi-dataset-no-reboot.nix;
  test-pull-reboot-after-backup = mkTest ./pull-reboot-after-backup.nix;
  test-pull-reboot-after-create = mkTest ./pull-reboot-after-create.nix;
  test-pull-reboot-after-destroy = mkTest ./pull-reboot-after-destroy.nix;
  test-pull-reboot-after-restore = mkTest ./pull-reboot-after-restore.nix;
  test-pull-reboot-all = mkTest ./pull-reboot-all.nix;
  test-pull-reboot-all-canmount-noauto = mkTest ./pull-reboot-all-canmount-noauto.nix;
  test-pull-reboot-all-canmount-on = mkTest ./pull-reboot-all-canmount-on.nix;
  test-pull-reboot-all-multi-dataset = mkTest ./pull-reboot-all-multi-dataset.nix;
  test-pull-simple-encrypted = mkTest ./pull-simple-encrypted.nix;
}
