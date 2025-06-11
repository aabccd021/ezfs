{
  lib,
  config,
  pkgs,
  ...
}:
let

  dsToPool = ds: lib.elemAt (lib.splitString "/" ds) 0;

  mapDataset =
    fn:
    lib.mkMerge (
      lib.mapAttrsToList (
        dsId: cfg:
        lib.mkIf cfg.enable (fn {
          dsId = dsId;
          cfg = cfg;
        })
      ) config.ezfs.datasets
    );

  mapTarget =
    fn:
    lib.mkMerge (
      lib.mapAttrsToList (
        backupId: backupCfg:
        lib.mkIf backupCfg.enable (fn {
          dsCfg = config.ezfs.datasets.${backupCfg.source};
          backupId = backupId;
          cfg = backupCfg;
        })
      ) config.ezfs.pull-backups
    );

  mapSource =
    fn:
    lib.mkMerge (
      lib.mapAttrsToList (
        backupId: backupCfg:
        let
          dsCfg = config.ezfs.datasets.${backupCfg.source};
        in
        lib.mkIf dsCfg.enable (fn {
          dsId = backupCfg.source;
          cfg = backupCfg;
        })
      ) config.ezfs.pull-backups
    );

  knownHost =
    cfg:
    pkgs.writeText "known-host" ''
      ${cfg.host} ${config.ezfs.sshdPublicKey}
    '';

  sshKey = backupId: "ezfs_pull_backup_ssh_key_${backupId}";

  source = dsCfg: cfg: "${cfg.user}@${cfg.host}:${dsCfg.name}";

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
            name = lib.mkOption {
              type = lib.types.str;
            };
            options = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
            };
            dependsOn = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            sanoidConfig = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
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
          };
        }
      );
    };
    pull-backups = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "Enable the pull backup from source dataset";
            source = lib.mkOption {
              type = lib.types.str;
            };
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
            dataset = lib.mkOption {
              type = lib.types.str;
            };
            sanoidConfig = lib.mkOption {
              type = lib.types.attrsOf lib.types.anything;
              default = { };
            };
            publicKey = lib.mkOption {
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
        }
      );
    };
  };

  config = lib.mkMerge [
    {
      systemd = mapDataset (
        { dsId, cfg, ... }:
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

          pullBackups = (lib.filterAttrs (n: v: v.source == dsId) config.ezfs.pull-backups);

          userAllows = lib.mapAttrs' (tds: tdsCfg: {
            name = tdsCfg.user;
            value = [
              "send"
              "hold"
              "bookmark"
            ];
          }) pullBackups;

          users = lib.mapAttrsToList (tds: tdsCfg: tdsCfg.user) pullBackups;

          requiredServices = (builtins.map (n: "ezfs-setup-${n}.service") cfg.dependsOn);

        in
        {
          services."ezfs-setup-${dsId}" = {
            description = "Mount ZFS dataset ${dsId}";
            restartIfChanged = true;
            serviceConfig.Type = "oneshot";
            after = [
              "zfs-import.target"
              "sops-install-secrets.service"
            ] ++ requiredServices;
            requires = requiredServices;
            wantedBy = [ "multi-user.target" ];
            path = [ "/run/booted-system/sw/" ];
            enableStrictShellChecks = true;
            environment.DATASET = cfg.name;
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
                lib.mapAttrsToList (n: v: "zfs allow -u ${n} ${lib.concatStringsSep "," v} ${cfg.name}") userAllows
              )}
            '';
          };
        }
      );
    }
    {
      boot = mapTarget (
        { cfg, ... }:
        {
          zfs.extraPools = [ (dsToPool cfg.dataset) ];
          zfs.devNodes = lib.mkDefault "/dev/disk/by-path";
        }
      );
      sops = mapTarget (
        { backupId, cfg, ... }:
        {
          secrets.${sshKey backupId} = cfg.privateKey // {
            owner = config.services.syncoid.user;
            group = config.services.syncoid.group;
          };
        }
      );
      services = mapTarget (
        {
          backupId,
          dsCfg,
          cfg,
          ...
        }:
        {
          sanoid.enable = true;
          sanoid.datasets.${cfg.dataset} = cfg.sanoidConfig;
          syncoid.enable = true;
          syncoid.commands."pull-backup-${backupId}" = {
            sshKey = config.sops.secrets.${sshKey backupId}.path;
            source = source dsCfg cfg;
            target = cfg.dataset;
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
      );
      environment = mapTarget (
        {
          backupId,
          dsCfg,
          cfg,
          ...
        }:
        {
          systemPackages = [
            (pkgs.writeShellApplication {
              name = "ezfs-restore-pull-backup-${backupId}";
              runtimeInputs = [ config.services.syncoid.package ];
              text = ''
                # recvoptions u: Prevent auto mounting the dataset after restore. Just mount it manually.
                exec syncoid \
                ${lib.optionalString (cfg.restoreExtraArgs != [ ]) (lib.escapeShellArg cfg.restoreExtraArgs)} \
                --sshkey ${config.sops.secrets.${sshKey backupId}.path} \
                --sshoption='StrictHostKeyChecking=yes' \
                --sshoption='UserKnownHostsFile=${knownHost cfg}' \
                --no-sync-snap \
                --no-privilege-elevation \
                --sendoptions="w" \
                --recvoptions="u" \
                ${cfg.dataset} \
                ${source dsCfg cfg}
              '';
            })
          ];
        }
      );
    }
    {

      services = mapDataset (
        { cfg, ... }:
        {
          sanoid.enable = true;
          sanoid.datasets.${cfg.name} = cfg.sanoidConfig;
        }
      );

      boot = mapDataset (
        { cfg, ... }:
        {
          zfs.extraPools = [ (dsToPool cfg.name) ];
          zfs.devNodes = lib.mkDefault "/dev/disk/by-path";
        }
      );
      assertions = mapDataset (
        { dsId, cfg, ... }:
        [
          {
            assertion =
              let
                canmount = lib.attrByPath [ "canmount" ] "" cfg.options;
              in
              canmount == "noauto" || canmount == "on" || canmount == "";
            message = "Option 'ezfs.datasets.\"${dsId}\".options.canmount' must be set to 'noauto' or 'on'";
          }
          {
            assertion = config.services.openssh.hostKeys != [ ];
            message = "services.openssh.hostKeys must be set for ezfs to work";
          }
        ]
      );
      environment = mapDataset (
        { dsId, cfg, ... }:
        let
          pullBackups = (lib.filterAttrs (n: v: v.source == dsId) config.ezfs.pull-backups);
          users = lib.mapAttrsToList (tds: tdsCfg: tdsCfg.user) pullBackups;
        in
        {
          systemPackages = [
            pkgs.mbuffer
            pkgs.lzop

            (pkgs.writeShellApplication {
              name = "ezfs-create-${dsId}";
              runtimeInputs = [ "/run/booted-system/sw" ];
              text = ''
                zfs create -u ${
                  lib.concatStringsSep " " (lib.mapAttrsToList (n: v: "-o ${n}=${v}") cfg.options)
                } ${cfg.name}
              '';
            })

            (pkgs.writeShellApplication {
              name = "ezfs-prepare-pull-restore-${dsId}";
              runtimeInputs = [ "/run/booted-system/sw" ];
              runtimeEnv.USERS = lib.concatStringsSep " " users;
              runtimeEnv.DATASET = cfg.name;
              # TODO: only allow user that actually requires access, not all backup users
              text = ''
                pool=$(echo "$DATASET" | cut -d'/' -f1)
                for user in $USERS; do
                zfs allow -u "$user" create,receive,mount "$pool"
                done
              '';
            })
          ];
        }
      );
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
    }
  ];
}
