{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.age-mock;

  # Hardcoded test keypair
  publicKey = "age1d6s9ne45qkchp5y9v5s527jw7zzu055jcwd2smgy70epwyz7pd8qmx82ft";
  privateKey = "AGE-SECRET-KEY-14YX9K83AY8RAZX3P0CYGK60RRE9XHYC6ZY9XSM7PMTRGL6QVAH2SSFPGLS";

  mkAgeFile =
    secretCfg:
    let
      name = secretCfg._module.args.name;
      plain = pkgs.writeText "${name}.txt" secretCfg.value;
    in
    pkgs.runCommand "${name}.age" { } ''
      ${pkgs.age}/bin/age -r ${publicKey} -o "$out" ${plain}
    '';

in
{
  options.age-mock = {
    enable = lib.mkEnableOption "age-mock";
    identityPath = lib.mkOption {
      type = lib.types.path;
      default = "/run/age-mock-identity.txt";
      readOnly = true;
    };
    secrets = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }:
          {
            options.value = lib.mkOption {
              type = lib.types.str;
            };
            options.file = lib.mkOption {
              type = lib.types.path;
              readOnly = true;
            };
            config.file = mkAgeFile config;
          }
        )
      );
    };
  };

  config = lib.mkIf cfg.enable {
    boot.initrd.postDeviceCommands = ''
      printf "${privateKey}" > /run/age-mock-identity.txt
      chmod 400 /run/age-mock-identity.txt
    '';
  };
}
