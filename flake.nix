{

  nixConfig.allow-import-from-derivation = false;

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

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

      formatter = treefmtEval.config.build.wrapper;

      tests = import ./tests {
        pkgs = pkgs;
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
