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
        dsId: dsCfg:
        lib.mkIf (dsCfg.enable && (config.networking.hostId == dsCfg.hostId)) (fn {
          dsId = dsId;
          cfg = dsCfg;
        })
      ) config.ezfs.datasets
    );

  mapPushTarget =
    fn:
    lib.mkMerge (
      lib.mapAttrsToList (
        backupId: backupCfg:
        lib.mkIf backupCfg.enable (fn {
          dsCfg = config.ezfs.datasets.${backupCfg.source};
          backupId = backupId;
          cfg = backupCfg;
        })
      ) config.ezfs.push-backups
    );

  mapPushSource =
    fn:
    lib.mkMerge (
      lib.mapAttrsToList (
        backupId: backupCfg:
        let
          dsCfg = config.ezfs.datasets.${backupCfg.source};
        in
        lib.mkIf (dsCfg.enable && (config.networking.hostId == dsCfg.hostId)) (fn {
          dsCfg = dsCfg;
          dsId = backupCfg.source;
          backupId = backupId;
          cfg = backupCfg;
        })
      ) config.ezfs.push-backups
    );

  mapPullTarget =
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

  mapPullSource =
    fn:
    lib.mkMerge (
      lib.mapAttrsToList (
        backupId: backupCfg:
        let
          dsCfg = config.ezfs.datasets.${backupCfg.source};
        in
        lib.mkIf (dsCfg.enable && (config.networking.hostId == dsCfg.hostId)) (fn {
          dsCfg = dsCfg;
          dsId = backupCfg.source;
          backupId = backupId;
          cfg = backupCfg;
        })
      ) config.ezfs.pull-backups
    );

  pullKnownHost =
    backupCfg:
    let
      hostId = config.ezfs.datasets.${backupCfg.source}.hostId;
      publicKey = config.ezfs.hosts.${hostId}.publicKey;
    in
    pkgs.writeText "known-host" ''
      ${backupCfg.host} ${publicKey}
    '';

  pushKnownHost =
    pushCfg:
    let
      hostId = pushCfg.hostId;
      publicKey = config.ezfs.hosts.${hostId}.publicKey;
    in
    pkgs.writeText "known-host" ''
      ${pushCfg.host} ${publicKey}
    '';

  pullSshKey = backupId: "ezfs_pull_backup_ssh_key_${backupId}";

  pushSshKey = backupId: "ezfs_push_backup_ssh_key_${backupId}";

  pullSource = dsCfg: cfg: "${cfg.user}@${cfg.host}:${dsCfg.name}";

  pushTarget = cfg: "${cfg.user}@${cfg.host}:${cfg.dataset}";

in
{
  options.ezfs = {
    hosts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
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
      default = { };
    };
    datasets = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            hostId = lib.mkOption {
              type = lib.types.str;
            };
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
    push-backups = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "Enable the push backup to target dataset";
            source = lib.mkOption {
              type = lib.types.str;
            };
            pushExtraArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            restoreExtraArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            hostId = lib.mkOption {
              type = lib.types.str;
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
      assertions =
        let
          hostIds = lib.lists.unique (lib.mapAttrsToList (dsName: dsCfg: dsCfg.hostId) config.ezfs.datasets);
        in
        builtins.map (
          hostId:
          let
            datasets = builtins.attrValues config.ezfs.datasets;
            hostIdDatasets = builtins.filter (ds: ds.hostId == hostId) datasets;
            names = builtins.map (ds: ds.name) hostIdDatasets;
            namesUnique = lib.lists.unique names;
            namesStr = builtins.concatStringsSep ", " names;
          in
          {
            assertion = builtins.length namesUnique == builtins.length names;
            message = ''
              Duplicate dataset name is found for hostId ${config.networking.hostId}: ${namesStr}
            '';
          }
        ) hostIds;
    }
    {
      assertions =
        builtins.map
          (
            type:
            let
              typeHostKeys = builtins.filter (k: k.type == type) config.services.openssh.hostKeys;
              paths = builtins.map (k: k.path) typeHostKeys;
              uniquePaths = lib.lists.unique paths;
              uniqueLength = builtins.length uniquePaths;
              pathsStr = builtins.concatStringsSep ", " uniquePaths;
            in
            {
              assertion = uniqueLength <= 1;
              message = ''
                Duplicate SSH host key with type ${type} is found: ${pathsStr}
                SSH doesn't support multiple host keys of the same type
              '';
            }
          )
          [
            "ed25519"
            "rsa"
            "ecdsa"
            "dsa"
          ];
    }
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
          # TODO rename to ezfs-setup-dataset-${dsId}
          # TODO rename all cfg to pullCfg
          # TODO rename all to target & source
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
      boot = mapPullTarget (
        { cfg, ... }:
        {
          zfs.extraPools = [ (dsToPool cfg.dataset) ];
          zfs.devNodes = lib.mkDefault "/dev/disk/by-path";
        }
      );
      sops = mapPullTarget (
        { backupId, cfg, ... }:
        {
          secrets.${pullSshKey backupId} = cfg.privateKey // {
            owner = config.services.syncoid.user;
            group = config.services.syncoid.group;
          };
        }
      );
      services = mapPullTarget (
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
            sshKey = config.sops.secrets.${pullSshKey backupId}.path;
            source = pullSource dsCfg cfg;
            target = cfg.dataset;
            # w = send dataset as is, not decrypted on transfer when the source dataset is encrypted
            sendOptions = "w";
            # u = don't mount the dataset after restore
            recvOptions = "u o canmount=off o mountpoint=none o keylocation=file:///dev/null";
            extraArgs = cfg.pullExtraArgs ++ [
              "--sshoption='StrictHostKeyChecking=yes'"
              "--sshoption='UserKnownHostsFile=${pullKnownHost cfg}'"
              # don't create new snapshot on source before backup, since we already created it with sanoid
              "--no-sync-snap"
              # no cons of using this,
              # don't forget to run `zfs allow -u <username> bookmark <pool>/<dataset>` on the remote host
              "--create-bookmark"
            ];
          };
        }
      );
      environment = mapPullTarget (
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
                --sshkey ${config.sops.secrets.${pullSshKey backupId}.path} \
                --sshoption='StrictHostKeyChecking=yes' \
                --sshoption='UserKnownHostsFile=${pullKnownHost cfg}' \
                --no-sync-snap \
                --no-privilege-elevation \
                --sendoptions="w" \
                --recvoptions="u" \
                ${cfg.dataset} \
                ${pullSource dsCfg cfg}
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
        {
          systemPackages = [
            (pkgs.writeShellApplication {
              name = "ezfs-create-${dsId}";
              runtimeInputs = [ "/run/booted-system/sw" ];
              text = ''
                zfs create -u ${
                  lib.concatStringsSep " " (lib.mapAttrsToList (n: v: "-o ${n}=${v}") cfg.options)
                } ${cfg.name}
              '';
            })

          ];
        }
      );
    }
    {
      services = mapPullSource (
        { ... }:
        let
          hostId = config.networking.hostId;
          publicKey = config.ezfs.hosts.${hostId}.publicKey;
        in
        {
          openssh = {
            enable = true;
            allowSFTP = lib.mkDefault false;
            settings = {
              PasswordAuthentication = lib.mkDefault false;
              PubkeyAuthentication = true;
              KbdInteractiveAuthentication = lib.mkDefault false;
              AllowTcpForwarding = lib.mkDefault false;
              X11Forwarding = lib.mkDefault false;
              AllowAgentForwarding = lib.mkDefault false;
              AllowStreamLocalForwarding = lib.mkDefault false;
              AuthenticationMethods = lib.mkDefault "publickey";
              DisableForwarding = lib.mkDefault true;
            };
            hostKeys = [
              {
                type = lib.elemAt (lib.splitString " " publicKey) 0;
                path = config.sops.secrets."ezfs_sshd_key".path;
              }
            ];
          };
        }
      );

      sops = mapPullSource (
        {
          ...
        }:
        let
          hostId = config.networking.hostId;
          privateKey = config.ezfs.hosts.${hostId}.privateKey;
        in
        {
          secrets."ezfs_sshd_key" = privateKey // {
            owner = "root";
            group = "root";
          };
        }
      );

      users = mapPullSource (
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

      environment = mapPullSource (
        {
          backupId,
          dsCfg,
          cfg,
          ...
        }:
        {
          systemPackages = [
            pkgs.mbuffer
            pkgs.lzop

            (pkgs.writeShellApplication {
              name = "ezfs-prepare-restore-pull-backup-${backupId}";
              runtimeInputs = [ "/run/booted-system/sw" ];
              runtimeEnv.DATASET = dsCfg.name;
              runtimeEnv.USER = cfg.user;
              text = ''
                pool=$(echo "$DATASET" | cut -d'/' -f1)
                zfs allow -u "$USER" create,receive,mount "$pool"
              '';
            })
          ];
        }
      );
    }
    {
      systemd = mapPushTarget (
        {
          backupId,
          cfg,
          ...
        }:
        {
          services."ezfs-setup-push-backup-${backupId}" = {
            description = "Setup ZFS push backup ${backupId}";
            restartIfChanged = true;
            serviceConfig.Type = "oneshot";
            after = [ "zfs-import.target" ];
            wantedBy = [ "multi-user.target" ];
            path = [ "/run/booted-system/sw/" ];
            environment.DATASET = cfg.dataset;
            environment.USER = cfg.user;
            script = ''
              set -x
              pool=$(echo "$DATASET" | cut -d'/' -f1)
              zfs unallow -u "$USER" "$pool"
              zfs allow -u "$USER" create,receive,mount "$pool"
            '';
          };

        }
      );
      environment = mapPushTarget (
        {
          backupId,
          cfg,
          ...
        }:
        {
          systemPackages = [
            pkgs.mbuffer
            pkgs.lzop
            (pkgs.writeShellApplication {
              name = "ezfs-prepare-restore-push-backup-${backupId}";
              runtimeInputs = [ "/run/booted-system/sw" ];
              runtimeEnv.DATASET = cfg.dataset;
              runtimeEnv.USER = cfg.user;
              text = ''
                zfs allow -u "$USER" send,hold,bookmark "$DATASET"
              '';
            })
          ];
        }
      );
      services = mapPushTarget (
        { ... }:
        let
          hostId = config.networking.hostId;
          publicKey = config.ezfs.hosts.${hostId}.publicKey;
        in
        {
          openssh = {
            enable = true;
            allowSFTP = lib.mkDefault false;
            settings = {
              PasswordAuthentication = lib.mkDefault false;
              PubkeyAuthentication = true;
              KbdInteractiveAuthentication = lib.mkDefault false;
              AllowTcpForwarding = lib.mkDefault false;
              X11Forwarding = lib.mkDefault false;
              AllowAgentForwarding = lib.mkDefault false;
              AllowStreamLocalForwarding = lib.mkDefault false;
              AuthenticationMethods = lib.mkDefault "publickey";
              DisableForwarding = lib.mkDefault true;
            };
            hostKeys = [
              {
                type = lib.elemAt (lib.splitString " " publicKey) 0;
                path = config.sops.secrets."ezfs_sshd_key".path;
              }
            ];
          };
        }
      );

      sops = mapPushTarget (
        {
          ...
        }:
        let
          hostId = config.networking.hostId;
          privateKey = config.ezfs.hosts.${hostId}.privateKey;
        in
        {
          secrets."ezfs_sshd_key" = privateKey // {
            owner = "root";
            group = "root";
          };
        }
      );

      users = mapPushTarget (
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
    {
      sops = mapPushSource (
        { backupId, cfg, ... }:
        {
          secrets.${pushSshKey backupId} = cfg.privateKey // {
            owner = config.services.syncoid.user;
            group = config.services.syncoid.group;
          };
        }
      );
      services = mapPushSource (
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
          syncoid.commands."push-backup-${backupId}" = {
            sshKey = config.sops.secrets.${pushSshKey backupId}.path;
            source = dsCfg.name;
            target = pushTarget cfg;
            # w = send dataset as is, not decrypted on transfer when the source dataset is encrypted
            sendOptions = "w";
            # u = don't mount the dataset after restore
            recvOptions = "u o canmount=off o mountpoint=none o keylocation=file:///dev/null";
            extraArgs = cfg.pushExtraArgs ++ [
              "--sshoption='StrictHostKeyChecking=yes'"
              "--sshoption='UserKnownHostsFile=${pushKnownHost cfg}'"
              # don't create new snapshot on source before backup, since we already created it with sanoid
              "--no-sync-snap"
              # no cons of using this,
              # don't forget to run `zfs allow -u <username> bookmark <pool>/<dataset>` on the remote host
              "--create-bookmark"
              "--debug"
            ];
          };
        }
      );
      environment = mapPushSource (
        {
          backupId,
          dsCfg,
          cfg,
          ...
        }:
        {
          systemPackages = [
            (pkgs.writeShellApplication {
              name = "ezfs-restore-push-backup-${backupId}";
              runtimeInputs = [ config.services.syncoid.package ];
              text = ''
                # recvoptions u: Prevent auto mounting the dataset after restore. Just mount it manually.
                exec syncoid \
                ${lib.optionalString (cfg.restoreExtraArgs != [ ]) (lib.escapeShellArg cfg.restoreExtraArgs)} \
                --sshkey ${config.sops.secrets.${pushSshKey backupId}.path} \
                --sshoption='StrictHostKeyChecking=yes' \
                --sshoption='UserKnownHostsFile=${pushKnownHost cfg}' \
                --no-sync-snap \
                --no-privilege-elevation \
                --sendoptions="w" \
                --recvoptions="u" \
                --debug \
                ${pushTarget cfg} \
                ${dsCfg.name}
              '';
            })
          ];
        }
      );
    }
  ];
}
