{ pkgs, inputs }:
let
  mkTest =
    nixFile:
    import nixFile {
      pkgs = pkgs;
      inputs = inputs;
    };
in
{
  test01 = mkTest ./test01.nix;
}
