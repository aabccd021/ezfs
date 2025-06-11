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

          requiredServices = (builtins.map (n: "ezfs-setup-${n}.service") dsCfg.dependsOn);

        in
        {
          # TODO rename to ezfs-setup-dataset-${dsId}
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
          zfs.extraPools = [ (dsToPool pullCfg.targetDatasetName) ];
          zfs.devNodes = lib.mkDefault "/dev/disk/by-path";
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

      services = mapPullTarget (
        {
          pullId,
          pullCfg,
          dsCfg,
          ...
        }:
        {
          sanoid.enable = true;
          sanoid.datasets.${pullCfg.targetDatasetName} = pullCfg.sanoidConfig;
          syncoid.enable = true;
          syncoid.commands."pull-backup-${pullId}" = {
            sshKey = config.sops.secrets.${pullSshKey pullId}.path;
            source = pullSource dsCfg pullCfg;
            target = pullCfg.targetDatasetName;
            # w = send dataset as is, not decrypted on transfer when the source dataset is encrypted
            sendOptions = "w";
            # u = don't mount the dataset after restore
            recvOptions = "u o canmount=off o mountpoint=none o keylocation=file:///dev/null";
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
          sanoid.datasets.${dsCfg.name} = dsCfg.sanoidConfig;
        }
      );

      boot = mapDataset (
        { dsCfg, ... }:
        {
          zfs.extraPools = [ (dsToPool dsCfg.name) ];
          zfs.devNodes = lib.mkDefault "/dev/disk/by-path";
        }
      );

      assertions = mapDataset (
        { dsId, dsCfg, ... }:
        [
          {
            assertion =
              let
                canmount = lib.attrByPath [ "canmount" ] "" dsCfg.options;
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
        { dsId, dsCfg, ... }:
        {
          systemPackages = [
            (pkgs.writeShellApplication {
              name = "ezfs-create-${dsId}";
              runtimeInputs = [ "/run/booted-system/sw" ];
              text = ''
                zfs create -u ${
                  lib.concatStringsSep " " (lib.mapAttrsToList (n: v: "-o ${n}=${v}") dsCfg.options)
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
      systemd = mapPushTarget (
        { pushId, pushCfg, ... }:
        {
          services."ezfs-setup-push-backup-${pushId}" = {
            description = "Setup ZFS push backup ${pushId}";
            restartIfChanged = true;
            serviceConfig.Type = "oneshot";
            after = [ "zfs-import.target" ];
            wantedBy = [ "multi-user.target" ];
            path = [ "/run/booted-system/sw/" ];
            environment.DATASET = pushCfg.targetDatasetName;
            environment.USER = pushCfg.user;
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
          sanoid.enable = true;
          sanoid.datasets.${pushCfg.targetDatasetName} = pushCfg.sanoidConfig;
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
