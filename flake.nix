{

  nixConfig.allow-import-from-derivation = false;

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";
  inputs.agenix.url = "github:ryantm/agenix";
  inputs.mock-secrets-nix.url = "github:aabccd021/mock-secrets-nix";

  outputs =
    { self, ... }@inputs:
    let

      nixosModules.default = import ./nixosModules/default.nix;

      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.deadnix.enable = true;
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
          agenix = inputs.agenix;
          age-mock-nix.nixosModules.default = import ./age-mock-nix;
          mock-secrets-nix = inputs.mock-secrets-nix;
          ezfs.nixosModules = nixosModules;
        };
      };

    in

    {

      checks.x86_64-linux = tests // {
        formatting = treefmtEval.config.build.check self;
      };

      packages.x86_64-linux.test-all = pkgs.linkFarm "ezfs-tests" (
        builtins.map (name: {
          inherit name;
          path = tests.${name};
        }) (builtins.attrNames tests)
      );

      formatter.x86_64-linux = treefmtEval.config.build.wrapper;

      nixosModules = nixosModules;

      devShells.x86_64-linux.default = pkgs.mkShellNoCC {
        buildInputs = [
          pkgs.nixd
        ];
      };

    };
}
