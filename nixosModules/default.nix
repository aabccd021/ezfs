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
          dsCfg = dsCfg;
        })
      ) config.ezfs.datasets
    );

  mapPushTarget =
    fn:
    lib.mkMerge (
      lib.mapAttrsToList (
        pushId: pushCfg:
        lib.mkIf pushCfg.enable (fn {
          dsCfg = config.ezfs.datasets.${pushCfg.sourceDatasetId};
          pushId = pushId;
          pushCfg = pushCfg;
        })
      ) config.ezfs.push-backups
    );

  mapPushSource =
    fn:
    lib.mkMerge (
      lib.mapAttrsToList (
        pushId: pushCfg:
        let
          dsCfg = config.ezfs.datasets.${pushCfg.sourceDatasetId};
        in
        lib.mkIf (dsCfg.enable && (config.networking.hostId == dsCfg.hostId)) (fn {
          dsCfg = dsCfg;
          pushId = pushId;
          pushCfg = pushCfg;
        })
      ) config.ezfs.push-backups
    );

  mapPullTarget =
    fn:
    lib.mkMerge (
      lib.mapAttrsToList (
        pullId: pullCfg:
        lib.mkIf pullCfg.enable (fn {
          dsCfg = config.ezfs.datasets.${pullCfg.sourceDatasetId};
          pullId = pullId;
          pullCfg = pullCfg;
        })
      ) config.ezfs.pull-backups
    );

  mapPullSource =
    fn:
    lib.mkMerge (
      lib.mapAttrsToList (
        pullId: pullCfg:
        let
          dsCfg = config.ezfs.datasets.${pullCfg.sourceDatasetId};
        in
        lib.mkIf (dsCfg.enable && (config.networking.hostId == dsCfg.hostId)) (fn {
          dsId = pullCfg.sourceDatasetId;
          dsCfg = dsCfg;
          pullId = pullId;
          pullCfg = pullCfg;
        })
      ) config.ezfs.pull-backups
    );

  pullKnownHost =
    pushCfg:
    let
      hostId = config.ezfs.datasets.${pushCfg.sourceDatasetId}.hostId;
      publicKey = config.ezfs.hosts.${hostId}.publicKey;
    in
    pkgs.writeText "known-host" ''
      ${pushCfg.host} ${publicKey}
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

  pullSshKey = pushId: "ezfs_pull_backup_ssh_key_${pushId}";

  pushSshKey = pushId: "ezfs_push_backup_ssh_key_${pushId}";

  pullSource = dsCfg: cfg: "${cfg.user}@${cfg.host}:${dsCfg.name}";

  pushTarget = pushCfg: "${pushCfg.user}@${pushCfg.host}:${pushCfg.targetDatasetName}";

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
        lib.types.submodule (
          { config, ... }:
          {
            options = {
              enable = lib.mkEnableOption "Enable the pull backup from source dataset";
              backupService = lib.mkOption {
                type = lib.types.str;
                readOnly = true;
                default = "syncoid-pull-backup-${config._module.args.name}.service";
              };
              sourceDatasetId = lib.mkOption {
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
              targetDatasetName = lib.mkOption {
                type = lib.types.str;
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
        )
      );
    };
    push-backups = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "Enable the push backup to target dataset";
            backupService = lib.mkOption {
              type = lib.types.str;
              readOnly = true;
              default = "syncoid-push-backup-${config._module.args.name}.service";
            };
            sourceDatasetId = lib.mkOption {
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
            targetDatasetName = lib.mkOption {
              type = lib.types.str;
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
      # canmount needs to be set to "noauto" to avoid being mounted automatically by NixOS,
      # which will ignore `ezfs.datasets.<dataset>.dependsOn`.
      assertions = mapDataset (
        { dsCfg, ... }:
        [
          {
            assertion = !(builtins.hasAttr "canmount" dsCfg.options);
            message = "Option 'canmount' can not be configured";
          }
        ]
      );
      systemd = mapDataset (
        { dsId, dsCfg, ... }:
        let
          updateOptions = builtins.removeAttrs dsCfg.options [
            "encryption"
            "casesensitivity"
            "utf8only"
            "normalization"
            "volblocksize"
            "pbkdf2iters"
            "pbkdf2salt"
            "keyformat"
          ];

          finalUpdateOptions = updateOptions // {
            canmount = "noauto";
          };

          pullBackups = (
            lib.filterAttrs (pullId: pullCfg: pullCfg.sourceDatasetId == dsId) config.ezfs.pull-backups
          );

          userAllows = lib.mapAttrs' (tds: tdsCfg: {
            name = tdsCfg.user;
            value = [
              "send"
              "hold"
              "bookmark"
            ];
          }) pullBackups;

          users = lib.mapAttrsToList (tds: tdsCfg: tdsCfg.user) pullBackups;

          pool = dsToPool dsCfg.name;

          requiredServices = (builtins.map (n: "ezfs-setup-dataset-${n}.service") dsCfg.dependsOn);

        in
        {
          services."ezfs-setup-dataset-${dsId}" = {
            description = "Mount ZFS dataset ${dsId}";
            restartIfChanged = true;
            serviceConfig.Type = "oneshot";
            after = [
              "sops-install-secrets.service"
              "zfs-import-${pool}.service"
              "zfs.target"
              "zfs-import.target"
              "zfs-mount.service"
            ] ++ requiredServices;
            wants = [
              "sops-install-secrets.service"
              "zfs-import-${pool}.service"
              "zfs.target"
              "zfs-import.target"
              "zfs-mount.service"
            ];
            requires = requiredServices;
            wantedBy = [ "multi-user.target" ];
            path = [ "/run/booted-system/sw/" ];
            enableStrictShellChecks = true;
            environment.DATASET = dsCfg.name;
            environment.USER = dsCfg.user;
            environment.GROUP = dsCfg.group;
            environment.BACKUP_USERS = lib.concatStringsSep " " users;
            script = ''
              set -x
              setOption() {
                if [ "$(zfs get -H -o value "$1" "$DATASET")" != "$2" ]; then
                  zfs set "$1=$2" "$DATASET"
                fi
              }

              pool=$(echo "$DATASET" | cut -d'/' -f1)
              for user in $BACKUP_USERS; do
                zfs unallow -u "$user" "$pool"
              done

              ${lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: "setOption ${n} ${v}") finalUpdateOptions)}

              encryption=$(zfs get -H -o value encryption "$DATASET")
              if [ "$encryption" != "off" ]; then
                
                keystatus=$(zfs get -H -o value keystatus "$DATASET")
                if [ "$keystatus" != "available" ]; then
                  zfs load-key "$DATASET"
                fi
              fi

              mounted=$(zfs get -H -o value mounted "$DATASET")
              if [ "$mounted" != "yes" ]; then
                zfs mount "$DATASET"
              fi

              mountpoint=$(zfs get -H -o value mountpoint "$DATASET")
              if [ -d "$mountpoint" ]; then
                chown "$USER":"$GROUP" "$mountpoint"
              fi

              zfs unallow -u "$USER" "$DATASET"
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (
                  n: v: "zfs allow -u ${n} ${lib.concatStringsSep "," v} ${dsCfg.name}"
                ) userAllows
              )}
            '';
          };
        }
      );
    }
    {

      boot = mapPullTarget (
        { pullCfg, ... }:
        {
          supportedFilesystems = [ "zfs" ];

          zfs.extraPools = [ (dsToPool pullCfg.targetDatasetName) ];
          zfs.devNodes = lib.mkDefault "/dev/disk/by-path";
          # NixOS will create `zfs-import-<pool>.service` for each pool specified in
          #  `zfs.extraPools`.
          # If `keylocation` is set to `prompt`, it will ask for the encryption key.
          # If `keylocation` is set to wrong path like `/dev/null`, the service will fail to start.
          # Both will block the boot process, and prevent us from entering the interactive shell.
          #
          # This happens even with canmount=off and mountpoint=none.
          #
          # This option will disable that.
          zfs.requestEncryptionCredentials = lib.mkDefault false;
        }
      );

      sops = mapPullTarget (
        { pullId, pullCfg, ... }:
        {
          secrets.${pullSshKey pullId} = pullCfg.privateKey // {
            owner = config.services.syncoid.user;
            group = config.services.syncoid.group;
          };
        }
      );

      systemd = mapPullTarget (
        { pullId, pullCfg, ... }:
        let
          pool = dsToPool pullCfg.targetDatasetName;
        in
        {
          services."syncoid-pull-backup-${pullId}" = {
            wants = [
              "zfs-import-${pool}.service"
              "sops-install-secrets.service"
              "zfs.target"
              "zfs-import.target"
              "zfs-mount.service"
            ];
            after = [
              "zfs-import-${pool}.service"
              "sops-install-secrets.service"
              "zfs.target"
              "zfs-import.target"
              "zfs-mount.service"
            ];
          };
        }
      );

      services = mapPullTarget (
        {
          pullId,
          pullCfg,
          dsCfg,
          ...
        }:
        {
          sanoid.enable = true;
          sanoid.datasets.${pullCfg.targetDatasetName} = {
            autoprune = lib.mkDefault true;
          };
          syncoid.enable = true;
          syncoid.commands."pull-backup-${pullId}" = {
            sshKey = config.sops.secrets.${pullSshKey pullId}.path;
            source = pullSource dsCfg pullCfg;
            target = pullCfg.targetDatasetName;
            # w = send dataset as is, not decrypted on transfer when the source dataset is encrypted
            sendOptions = "w";
            # u = don't mount the dataset after restore
            recvOptions = "u o canmount=off o mountpoint=none o keylocation=file:///dev/null";
            localTargetAllow = [
              "canmount"
              "create"
              "keylocation"
              "mount"
              "mountpoint"
              "receive"
            ];
            extraArgs = pullCfg.pullExtraArgs ++ [
              "--sshoption='StrictHostKeyChecking=yes'"
              "--sshoption='UserKnownHostsFile=${pullKnownHost pullCfg}'"
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
          dsCfg,
          pullId,
          pullCfg,
          ...
        }:
        {
          systemPackages = [
            (pkgs.writeShellApplication {
              name = "ezfs-restore-pull-backup-${pullId}";
              runtimeInputs = [ config.services.syncoid.package ];
              text = ''
                # recvoptions u: Prevent auto mounting the dataset after restore. Just mount it manually.
                exec syncoid \
                ${
                  lib.optionalString (pullCfg.restoreExtraArgs != [ ]) (lib.escapeShellArg pullCfg.restoreExtraArgs)
                } \
                --sshkey ${config.sops.secrets.${pullSshKey pullId}.path} \
                --sshoption='StrictHostKeyChecking=yes' \
                --sshoption='UserKnownHostsFile=${pullKnownHost pullCfg}' \
                --no-sync-snap \
                --no-privilege-elevation \
                --sendoptions="w" \
                --recvoptions="u" \
                ${pullCfg.targetDatasetName} \
                ${pullSource dsCfg pullCfg}
              '';
            })
          ];
        }
      );
    }
    {

      services = mapDataset (
        { dsCfg, ... }:
        {
          sanoid.enable = true;
          sanoid.datasets.${dsCfg.name} = {
            autosnap = lib.mkDefault true;
            autoprune = lib.mkDefault true;
          };
        }
      );

      boot = mapDataset (
        { dsCfg, ... }:
        {
          zfs.extraPools = [ (dsToPool dsCfg.name) ];
          zfs.devNodes = lib.mkDefault "/dev/disk/by-path";
          supportedFilesystems = [ "zfs" ];
        }
      );

      environment = mapDataset (
        { dsId, dsCfg, ... }:
        let
          finalOptions = dsCfg.options // {
            canmount = "noauto";
          };
        in
        {
          systemPackages = [
            (pkgs.writeShellApplication {
              name = "ezfs-create-${dsId}";
              runtimeInputs = [ "/run/booted-system/sw" ];
              text = ''
                zfs create -u ${
                  lib.concatStringsSep " " (lib.mapAttrsToList (n: v: "-o ${n}=${v}") finalOptions)
                } ${dsCfg.name}
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
              PubkeyAuthentication = true;
              AuthenticationMethods = lib.mkDefault "publickey";
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
        { ... }:
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
        { pullCfg, ... }:
        {
          users.${pullCfg.user} = {
            isNormalUser = true;
            openssh.authorizedKeys.keys = [
              pullCfg.publicKey
            ];
          };
        }
      );

      environment = mapPullSource (
        {
          pullId,
          dsCfg,
          pullCfg,
          ...
        }:
        {
          systemPackages = [
            pkgs.mbuffer
            pkgs.lzop

            (pkgs.writeShellApplication {
              name = "ezfs-prepare-restore-pull-backup-${pullId}";
              runtimeInputs = [ "/run/booted-system/sw" ];
              runtimeEnv.DATASET = dsCfg.name;
              runtimeEnv.USER = pullCfg.user;
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

      boot = mapPushTarget (
        { pushCfg, ... }:
        {
          supportedFilesystems = [ "zfs" ];
          zfs.extraPools = [ (dsToPool pushCfg.targetDatasetName) ];
          zfs.devNodes = lib.mkDefault "/dev/disk/by-path";
          zfs.requestEncryptionCredentials = lib.mkDefault false;
        }
      );

      systemd = mapPushTarget (
        { pushId, pushCfg, ... }:
        let
          pool = dsToPool pushCfg.targetDatasetName;
        in
        {
          services."ezfs-setup-push-backup-${pushId}" = {
            description = "Setup ZFS push backup ${pushId}";
            restartIfChanged = true;
            serviceConfig.Type = "oneshot";
            after = [
              "sops-install-secrets.service"
              "zfs-import-${pool}.service"
              "zfs.target"
              "zfs-import.target"
              "zfs-mount.service"
            ];
            wants = [
              "sops-install-secrets.service"
              "zfs-import-${pool}.service"
              "zfs.target"
              "zfs-import.target"
              "zfs-mount.service"
            ];
            wantedBy = [ "multi-user.target" ];
            path = [ "/run/booted-system/sw/" ];
            environment.DATASET = pushCfg.targetDatasetName;
            environment.USER = pushCfg.user;
            script = ''
              set -x
              pool=$(echo "$DATASET" | cut -d'/' -f1)
              zfs unallow -u "$USER" "$pool"
              zfs allow -u "$USER" create,receive,mount "$pool"

              # if dataset already exists, we need to set the options
              if zfs list -H "$DATASET" >/dev/null 2>&1; then
                zfs allow -u "$USER" canmount,mountpoint,keylocation "$DATASET"
              fi
            '';
          };

        }
      );

      environment = mapPushTarget (
        { pushId, pushCfg, ... }:
        {
          systemPackages = [
            pkgs.mbuffer
            pkgs.lzop
            (pkgs.writeShellApplication {
              name = "ezfs-prepare-restore-push-backup-${pushId}";
              runtimeInputs = [ "/run/booted-system/sw" ];
              runtimeEnv.DATASET = pushCfg.targetDatasetName;
              runtimeEnv.USER = pushCfg.user;
              text = ''
                zfs allow -u "$USER" send,hold,bookmark "$DATASET"
              '';
            })
          ];
        }
      );

      services = mapPushTarget (
        { pushCfg, ... }:
        let
          hostId = config.networking.hostId;
          publicKey = config.ezfs.hosts.${hostId}.publicKey;
        in
        {
          sanoid.enable = true;
          sanoid.datasets.${pushCfg.targetDatasetName} = {
            autoprune = lib.mkDefault true;
          };
          openssh = {
            enable = true;
            allowSFTP = lib.mkDefault false;
            settings = {
              PubkeyAuthentication = true;
              AuthenticationMethods = lib.mkDefault "publickey";
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
        { ... }:
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
        { pushCfg, ... }:
        {
          users.${pushCfg.user} = {
            isNormalUser = true;
            openssh.authorizedKeys.keys = [
              pushCfg.publicKey
            ];
          };
        }
      );
    }
    {
      sops = mapPushSource (
        { pushId, pushCfg, ... }:
        {
          secrets.${pushSshKey pushId} = pushCfg.privateKey // {
            owner = config.services.syncoid.user;
            group = config.services.syncoid.group;
          };
        }
      );

      services = mapPushSource (
        {
          pushId,
          dsCfg,
          pushCfg,
          ...
        }:
        {
          syncoid.enable = true;
          syncoid.commands."push-backup-${pushId}" = {
            sshKey = config.sops.secrets.${pushSshKey pushId}.path;
            source = dsCfg.name;
            target = pushTarget pushCfg;
            # w = send dataset as is, not decrypted on transfer when the source dataset is encrypted
            sendOptions = "w";
            # u = don't mount the dataset after restore
            recvOptions = "u o canmount=off o mountpoint=none o keylocation=file:///dev/null";
            extraArgs = pushCfg.pushExtraArgs ++ [
              "--sshoption='StrictHostKeyChecking=yes'"
              "--sshoption='UserKnownHostsFile=${pushKnownHost pushCfg}'"
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
          pushId,
          dsCfg,
          pushCfg,
          ...
        }:
        {
          systemPackages = [
            (pkgs.writeShellApplication {
              name = "ezfs-restore-push-backup-${pushId}";
              runtimeInputs = [ config.services.syncoid.package ];
              text = ''
                # recvoptions u: Prevent auto mounting the dataset after restore. Just mount it manually.
                exec syncoid \
                ${
                  lib.optionalString (pushCfg.restoreExtraArgs != [ ]) (lib.escapeShellArg pushCfg.restoreExtraArgs)
                } \
                --sshkey ${config.sops.secrets.${pushSshKey pushId}.path} \
                --sshoption='StrictHostKeyChecking=yes' \
                --sshoption='UserKnownHostsFile=${pushKnownHost pushCfg}' \
                --no-sync-snap \
                --no-privilege-elevation \
                --sendoptions="w" \
                --recvoptions="u" \
                --debug \
                ${pushTarget pushCfg} \
                ${dsCfg.name}
              '';
            })
          ];
        }
      );
    }
  ];
}
