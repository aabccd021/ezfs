{
  lib,
  config,
  pkgs,
  ...
}:
# TODO: push backup
# TODO: mount multiple dataset in order
let

  mapDataset =
    fn:
    lib.mkMerge (lib.mapAttrsToList (ds: cfg: lib.mkIf cfg.enable (fn ds cfg)) config.ezfs.datasets);

  mapTarget =
    fn:
    lib.mkMerge (
      lib.mapAttrsToList (
        dsName: dsCfg:
        lib.mkMerge (
          lib.mapAttrsToList (
            backupName: backupCfg:
            lib.mkIf backupCfg.enable (fn {
              dsName = dsName;
              backupName = backupName;
              cfg = backupCfg;
            })
          ) dsCfg.pull-backup
        )
      ) config.ezfs.datasets
    );

  mapSource =
    fn:
    lib.mkMerge (
      lib.mapAttrsToList (
        dsName: dsCfg:
        lib.mkIf dsCfg.enable (
          lib.mkMerge (
            lib.mapAttrsToList (
              backupName: backupCfg:
              (fn {
                dsName = dsName;
                cfg = backupCfg;
              })
            ) dsCfg.pull-backup
          )
        )
      ) config.ezfs.datasets
    );

  formalName = builtins.replaceStrings [ "/" ] [ "-" ];

  knownHost =
    cfg:
    pkgs.writeText "known-host" ''
      ${cfg.host} ${config.ezfs.sshdPublicKey}
    '';

  sshKey = cfg: config.sops.secrets.${cfg.privateKeySopsName}.path;

  source = dsName: cfg: "${cfg.user}@${cfg.host}:${dsName}";

  pullOptions = lib.types.submodule {
    options = {
      enable = lib.mkEnableOption "Enable the pull backup from source dataset";
      pullExtraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      restoreExtraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      host = lib.mkOption {
        type = lib.types.str;
      };
      user = lib.mkOption {
        type = lib.types.str;
      };
      targetDataset = lib.mkOption {
        type = lib.types.str;
      };
      publicKey = lib.mkOption {
        type = lib.types.str;
      };
      privateKeySopsName = lib.mkOption {
        type = lib.types.str;
      };
      privateKey = lib.mkOption {
        type = lib.types.submodule {
          options = {
            sopsFile = lib.mkOption {
              type = lib.types.path;
            };
            key = lib.mkOption {
              type = lib.types.str;
            };
          };
        };
      };
    };
  };
in
{
  options.ezfs = {
    sshdPublicKey = lib.mkOption {
      type = lib.types.str;
    };
    datasets = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "Enable the ezfs module";
            options = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
            };
            user = lib.mkOption {
              type = lib.types.str;
              default = "root";
              description = "The user to own the mounted dataset.";
            };
            group = lib.mkOption {
              type = lib.types.str;
              default = "root";
              description = "The group to own the mounted dataset.";
            };
            pull-backup = lib.mkOption {
              type = lib.types.attrsOf pullOptions;
              default = { };
            };
          };
        }
      );
    };
  };

  config = lib.mkMerge [
    {
      systemd = mapDataset (
        ds: cfg:
        let

          updateOptions = builtins.removeAttrs cfg.options [
            "encryption"
            "casesensitivity"
            "utf8only"
            "normalization"
            "volblocksize"
            "pbkdf2iters"
            "pbkdf2salt"
            "keyformat"
          ];

          userAllows = lib.mapAttrs' (tds: tdsCfg: {
            name = tdsCfg.user;
            value = [
              "send"
              "hold"
              "bookmark"
            ];
          }) cfg.pull-backup;

          users = lib.mapAttrsToList (tds: tdsCfg: tdsCfg.user) cfg.pull-backup;

        in
        {
          services."ezfs-setup-${formalName ds}" = {
            description = "Mount ZFS dataset ${ds}";
            restartIfChanged = true;
            serviceConfig.Type = "oneshot";
            after = [
              "zfs-import.target"
              "sops-install-secrets.service"
            ];
            wantedBy = [ "multi-user.target" ];
            path = [ "/run/booted-system/sw/" ];
            enableStrictShellChecks = true;
            environment.DATASET = ds;
            environment.USER = cfg.user;
            environment.GROUP = cfg.group;
            environment.BACKUP_USERS = lib.concatStringsSep " " users;
            script = ''
              set -x
              setOption() {
                if [ "$(zfs get -H -o value "$1" "$DATASET")" != "$2" ]; then
                  zfs set "$1=$2" "$DATASET"
                fi
              }

              for user in $BACKUP_USERS; do
                zfs unallow -u "$user" "$DATASET"
              done

              ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: "setOption ${n} ${v}") updateOptions)}

              encryption=$(zfs get -H -o value encryption "$DATASET")
              if [ "$encryption" != "off" ]; then
                
                keystatus=$(zfs get -H -o value keystatus "$DATASET")
                if [ "$keystatus" != "available" ]; then
                  zfs load-key "$DATASET"
                fi
              fi

              if [ "$(zfs get -H -o value mounted "$DATASET")" != "yes" ]; then
                zfs mount "$DATASET"
              fi

              mountpoint=$(zfs get -H -o value mountpoint "$DATASET")
              chown "$USER":"$GROUP" "$mountpoint"

              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (n: v: "zfs allow -u ${n} ${lib.concatStringsSep "," v} ${ds}") userAllows
              )}

            '';
          };
        }
      );

    }
    {
      sops = mapTarget (
        { cfg, ... }:
        {
          secrets.${cfg.privateKeySopsName} = cfg.privateKey // {
            owner = config.services.syncoid.user;
            group = config.services.syncoid.group;
          };
        }
      );

    }
    {
      services = lib.mkMerge [
        (mapTarget (
          { dsName, cfg, ... }:
          {
            syncoid.enable = true;
            syncoid.commands."pull-backup-${formalName dsName}" = {
              sshKey = sshKey cfg;
              source = source dsName cfg;
              target = cfg.targetDataset;
              # w = send dataset as is, not decrypted on transfer when the source dataset is encrypted
              sendOptions = "w";
              # u = don't mount the dataset after restore
              recvOptions = "u o canmount=off o mountpoint=none o keylocation=file:///dev/null";
              extraArgs = cfg.pullExtraArgs ++ [
                "--sshoption='StrictHostKeyChecking=yes'"
                "--sshoption='UserKnownHostsFile=${knownHost cfg}'"
                # don't create new snapshot on source before backup, since we already created it with sanoid
                "--no-sync-snap"
                # no cons of using this,
                # don't forget to run `zfs allow -u <username> bookmark <pool>/<dataset>` on the remote host
                "--create-bookmark"
              ];
            };

          }
        ))
      ];

    }
    {
      environment = lib.mkMerge [
        (mapTarget (
          { dsName, cfg, ... }:
          {

            systemPackages = [
              (pkgs.writeShellApplication {
                name = "syncoid-pull-restore-${formalName dsName}";
                runtimeInputs = [ config.services.syncoid.package ];
                text = ''
                  # TODO: check if source dataset exists before running this script
                  # recvoptions u: Prevent auto mounting the dataset after restore. Just mount it manually.
                  exec syncoid \
                    ${lib.optionalString (cfg.restoreExtraArgs != [ ]) (lib.escapeShellArg cfg.restoreExtraArgs)} \
                    --sshkey ${sshKey cfg} \
                    --sshoption='StrictHostKeyChecking=yes' \
                    --sshoption='UserKnownHostsFile=${knownHost cfg}' \
                    --no-sync-snap \
                    --no-privilege-elevation \
                    --sendoptions="w" \
                    --recvoptions="u" \
                    ${cfg.targetDataset} \
                    ${source dsName cfg}
                '';
              })
            ];
          }
        ))
        (mapDataset (
          dsName: cfg:
          let

            users = lib.mapAttrsToList (tds: tdsCfg: tdsCfg.user) cfg.pull-backup;
          in
          {
            systemPackages = [
              pkgs.mbuffer
              pkgs.lzop

              (pkgs.writeShellApplication {
                name = "ezfs-create-${formalName dsName}";
                runtimeInputs = [ "/run/booted-system/sw" ];
                text = ''
                  zfs create -u ${
                    lib.concatStringsSep " " (lib.mapAttrsToList (n: v: "-o ${n}=${v}") cfg.options)
                  } ${dsName}
                '';
              })

              (pkgs.writeShellApplication {
                name = "ezfs-prepare-pull-restore-${formalName dsName}";
                runtimeInputs = [ "/run/booted-system/sw" ];
                runtimeEnv.USERS = lib.concatStringsSep " " users;
                runtimeEnv.DATASET = dsName;
                text = ''
                  # TODO: only allow user that actually requires access, 
                  # not all backup users for this dataset
                  pool=$(echo "$DATASET" | cut -d'/' -f1)
                  for user in $USERS; do
                    zfs allow -u "$user" create,receive,mount "$pool"
                  done
                '';
              })

            ];
          }
        ))
      ];

    }
    {
      users = mapSource (
        { cfg, ... }:
        {
          users.${cfg.user} = {
            isNormalUser = true;
            openssh.authorizedKeys.keys = [
              cfg.publicKey
            ];
          };
        }
      );
      boot = lib.mkMerge [
        (mapTarget (
          { cfg, ... }:
          let
            pool = lib.elemAt (lib.splitString "/" cfg.targetDataset) 0;
          in
          {
            zfs.extraPools = [ pool ];
            zfs.devNodes = lib.mkDefault "/dev/disk/by-path";
          }
        ))
        (mapDataset (
          dsName: cfg: {
            zfs.extraPools = [
              (lib.elemAt (lib.splitString "/" dsName) 0)
            ];
            zfs.devNodes = lib.mkDefault "/dev/disk/by-path";
          }
        ))
      ];

    }
    {
      assertions = mapDataset (
        dsName: cfg: [
          {
            assertion =
              let
                canmount = lib.attrByPath [ "canmount" ] "" cfg.options;
              in
              canmount == "noauto" || canmount == "on" || canmount == "";
            message = "ezfs.datasets.${dsName}.options.canmount must be set to 'noauto' or 'on'";
          }
        ]

      );
    }
    {
      assertions = [
        {
          assertion = config.services.openssh.hostKeys != [ ];
          message = "services.openssh.hostKeys must be set for ezfs to work";
        }
      ];

    }
  ];
}
