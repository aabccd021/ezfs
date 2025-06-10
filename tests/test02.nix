{
  pkgs,
  inputs,
  mockSecrets,
  ...
}:
let
  sharedModule = {
    ezfs = {
      sshdPublicKey = builtins.readFile mockSecrets.ed25519.alice.public;
      datasets."zpool/foo" = {
        options = {
          keyformat = "passphrase";
        };
        pull-backup.bckp = {
          host = "main.com";
          user = "foo-bckp";
          privateKey = {
            sopsFile = ../secrets.yaml;
            key = "name_of_key";
          };
          publicKey = mockSecrets.ed25519.bob.public;
        };
      };
    };
  };
in

pkgs.testers.runNixOSTest {
  name = "test01";

  nodes.main = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
      inputs.sops-nix-mock.nixosModules.default
      sharedModule
    ];

    ezfs.datasets."zroot/lawkwk" = {
      enable = true;
      options.keylocation = "file:///run/encryption_key.txt";
    };

    boot.initrd.postDeviceCommands = ''
      echo "encryption key" > /run/encryption_key.txt
    '';

    services.openssh.enable = true;
    services.openssh.hostKeys = [
      {
        path = mockSecrets.ed25519.bob.private;
        type = "ed25519";
      }
    ];

  };

  nodes.backup = {
    imports = [
      inputs.sops-nix.nixosModules.default
      inputs.ezfs.nixosModules.default
      inputs.sops-nix-mock.nixosModules.default
      sharedModule
    ];

    ezfs.datasets."zpool/foo".pull-backup.bckp = {
      enable = true;
      targetDataset = "backup_zpool/foo_backup";
    };

    # required for test only
    sops-mock.enable = true;
    sops-mock.secrets.ezfs_pull_backup_zpool_foo = builtins.readFile mockSecrets.ed25519.alice.private;

    # Required for allow-import-from-derivation = false;
    sops.validateSopsFiles = false;
  };

  testScript = "";
}
