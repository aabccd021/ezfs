{

  nixConfig.allow-import-from-derivation = false;

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.sops-nix.url = "github:Mic92/sops-nix";
  inputs.sops-nix-mock.url = "github:aabccd021/sops-nix-mock";
  inputs.mock-secrets-nix.url = "github:aabccd021/mock-secrets-nix";

  outputs =
    { self, ... }@inputs:
    let
      lib = inputs.nixpkgs.lib;

      collectInputs =
        is:
        pkgs.linkFarm "inputs" (
          builtins.mapAttrs (
            name: i:
            pkgs.linkFarm name {
              self = i.outPath;
              deps = collectInputs (lib.attrByPath [ "inputs" ] { } i);
            }
          ) is
        );

      nixosModules.default = import ./nixosModules/default.nix;

      nixosModules.ezfs = nixosModules.default;

      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.shfmt.enable = true;
        programs.shellcheck.enable = true;
        settings.formatter.shellcheck.options = [
          "-s"
          "sh"
        ];
      };

      formatter = treefmtEval.config.build.wrapper;

      tests = import ./tests {
        pkgs = pkgs;
        mockSecrets = inputs.mock-secrets-nix.lib.secrets;
        inputs = {
          sops-nix = inputs.sops-nix;
          sops-nix-mock = inputs.sops-nix-mock;
          ezfs.nixosModules = nixosModules;
        };
      };

      devShells.default = pkgs.mkShellNoCC {
        buildInputs = [
          pkgs.nixd
        ];
      };

      packages =
        tests
        // devShells
        // {
          formatting = treefmtEval.config.build.check self;
          formatter = formatter;
          allInputs = collectInputs inputs;
        };

    in

    {

      packages.x86_64-linux = packages // rec {
        gcroot = pkgs.linkFarm "gcroot" packages;
        default = gcroot;
      };

      checks.x86_64-linux = packages;
      formatter.x86_64-linux = formatter;
      devShells.x86_64-linux = devShells;
      nixosModules = nixosModules;

    };
}
