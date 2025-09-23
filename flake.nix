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

      nixosModules.default = import ./nixosModules/default.nix;

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

      tests = import ./tests {
        pkgs = pkgs;
        inputs = {
          sops-nix = inputs.sops-nix;
          sops-nix-mock = inputs.sops-nix-mock;
          mock-secrets-nix = inputs.mock-secrets-nix;
          ezfs.nixosModules = nixosModules;
        };
      };

    in

    {

      checks.x86_64-linux = tests // {
        formatting = treefmtEval.config.build.check self;
      };
      formatter.x86_64-linux = treefmtEval.config.build.wrapper;

      nixosModules = nixosModules;

      devShells.x86_64-linux.default = pkgs.mkShellNoCC {
        buildInputs = [
          pkgs.nixd
        ];
      };

    };
}
