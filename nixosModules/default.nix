{
  lib,
  config,
  pkgs,
  ...
}:
let

  dsToPool = ds: lib.elemAt (lib.splitString "/" ds) 0;

  # Every snapshot type sanoid knows, in sanoid.defaults.conf order.
  snapshotTypes = [
    "frequently"
    "hourly"
    "daily"
    "weekly"
    "monthly"
    "yearly"
  ];

  # The non-zero half of sanoid's own [template_default]. Reproduced here so
  # that every type this module emits is stated outright, which is the whole
  # point of the `snapshots` option -- see its description. Kept as the
  # default so this module's behaviour is unchanged for anyone who does not
  # set `snapshots`; the types sanoid defaults to 0 are filled in by
  # expandSnapshots below.
  sanoidDefaultCounts = {
    hourly = 48;
    daily = 90;
    monthly = 6;
  };

  # A `snapshots` value as a full set of sanoid keep counts: the counts asked
  # for, and an explicit 0 for every type that was not.
  #
  # Zeroing the rest is load-bearing rather than tidy. An unstated type is not
  # absent: it inherits template_default above, which is non-zero for hourly,
  # daily and monthly (sanoid's own defaults already hold frequently, weekly
  # and yearly at 0). Sanoid destroys a snapshot only when it is both older
  # than count * period *and* one of more than `count` snapshots of its type,
  # so under an inherited `daily = 90` a handful of stray daily snapshots
  # never exceeds the count and lives forever. An explicit 0 is the opposite
  # instruction: sanoid takes none and prunes any it finds.
  expandSnapshots =
    snapshots:
    let
      counts = if snapshots == "none" then { } else snapshots;
    in
    lib.mapAttrs (_: count: lib.mkDefault count) (lib.genAttrs snapshotTypes (_: 0) // counts);

  # Whether a `snapshots` value leaves sanoid taking any snapshot at all.
  # Sanoid only snapshots a type whose keep count is above 0, so "none", the
  # empty attribute set and an attribute set of all-zero counts all mean the
  # same thing here even though only the first turns autosnap off.
  takesSnapshots =
    snapshots: snapshots != "none" && lib.any (count: count > 0) (lib.attrValues snapshots);

  # Keep counts keyed by snapshot type. The key check is not cosmetic: an
  # unknown key reaches sanoid.conf verbatim and sanoid refuses to start at
  # all ("FATAL ERROR: I don't understand the setting ..."), taking every
  # other dataset's snapshotting and pruning down with it. A typo would also
  # leave the type it was meant to be at 0, silently pruning that type. Both
  # are caught here instead.
  snapshotCountsType =
    lib.types.addCheck (lib.types.attrsOf lib.types.ints.unsigned) (
      counts: lib.all (type: lib.elem type snapshotTypes) (lib.attrNames counts)
    )
    // {
      description = "sanoid keep counts keyed by ${lib.concatStringsSep ", " snapshotTypes}";
    };

  snapshotsOption =
    { default, description }:
    lib.mkOption {
      type = lib.types.either (lib.types.enum [ "none" ]) snapshotCountsType;
      inherit default;
      example = {
        daily = 7;
        weekly = 4;
        monthly = 12;
      };
      description = ''
        ${description}

        Either an attribute set of sanoid keep counts per snapshot type
        (${lib.concatStringsSep ", " snapshotTypes}), or the string "none".

        Types left out are held at 0 rather than inheriting sanoid's own
        defaults of hourly 48, daily 90, monthly 6. That distinction is the
        reason this option exists: sanoid prunes a type only once more than
        its count exist, so a type nothing fills can never prune, and a
        single snapshot landing in such a type is kept forever with nothing
        to indicate it. Stating every type closes that.

        "none" means take nothing and keep nothing: autosnap off and every
        count 0, so a snapshot made here by hand is cleaned up rather than
        immortal. Setting `services.sanoid.datasets.<name>.autosnap = false`
        by hand is not the same thing and is the mistake this replaces -- it
        stops sanoid taking snapshots while leaving those inherited counts in
        place.

        On a replication target autosnap is already off, so there "none"
        only means every count 0 -- sanoid destroys each snapshot as soon as
        syncoid lands it, which throws the backup away and makes the next run
        resend from scratch. It is almost never what you want on a target.
      '';
    };

  # Retention for snapshots that arrive on a replication target. syncoid runs
  # with --no-sync-snap, so every snapshot on a target was named by whatever
  # created it on the source, and sanoid on that side only prunes them.
  #
  # The default reproduces what this module did before the option existed,
  # which is worth reading twice before relying on it: weekly and yearly are
  # 0, so a source that takes weekly snapshots has them replicated to the
  # target and then destroyed on sanoid's next run. If the source keeps types
  # beyond hourly, daily and monthly, set this to match it.
  #
  # Shared verbatim by pull-backups and push-backups: both are the same
  # receiving side of the same replication.
  targetSnapshotsOption = snapshotsOption {
    default = sanoidDefaultCounts;
    description = "How many of each snapshot type sanoid keeps on this replication target.";
  };

  mapDataset =
    fn:
    lib.mkMerge (
      lib.mapAttrsToList (
        dsId: dsCfg:
        lib.mkIf (config.ezfs.enable && dsCfg.enable && config.networking.hostId == dsCfg.hostId) (fn {
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
        lib.mkIf (config.ezfs.enable && pushCfg.enable) (fn {
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
        lib.mkIf (config.ezfs.enable && dsCfg.enable && config.networking.hostId == dsCfg.hostId) (fn {
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
        lib.mkIf (config.ezfs.enable && pullCfg.enable) (fn {
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
        lib.mkIf (config.ezfs.enable && dsCfg.enable && config.networking.hostId == dsCfg.hostId) (fn {
          dsId = pullCfg.sourceDatasetId;
          dsCfg = dsCfg;
          pullId = pullId;
          pullCfg = pullCfg;
        })
      ) config.ezfs.pull-backups
    );

  pullKnownHost =
    pushCfg:
    pkgs.writeText "known-host" ''
      ${pushCfg.host} ${
        config.ezfs.hosts.${config.ezfs.datasets.${pushCfg.sourceDatasetId}.hostId}.publicKey
      }
    '';

  pushKnownHost =
    pushCfg:
    pkgs.writeText "known-host" ''
      ${pushCfg.host} ${config.ezfs.hosts.${pushCfg.hostId}.publicKey}
    '';

  mapResticBackup =
    fn:
    lib.mkMerge (
      lib.mapAttrsToList (
        resticId: resticCfg:
        let
          dsCfg = config.ezfs.datasets.${resticCfg.sourceDatasetId};
        in
        lib.mkIf (config.ezfs.enable && resticCfg.enable && config.networking.hostId == dsCfg.hostId) (fn {
          dsId = resticCfg.sourceDatasetId;
          dsCfg = dsCfg;
          resticId = resticId;
          resticCfg = resticCfg;
        })
      ) config.ezfs.restic-backups
    );

  # Fixed bind-mount target for the ZFS snapshot being backed up. It has to be
  # stable across runs so restic can match files against the parent snapshot;
  # see the comment in ezfs-restic-backup.sh.
  resticStablePath = resticId: "/run/ezfs-restic-${resticId}";
  resticCacheDir = resticId: "ezfs-restic-${resticId}";

  resticPasswordSecret = resticId: "ezfs_restic_password_${resticId}";
  resticAwsAccessKeySecret = resticId: "ezfs_restic_aws_access_key_${resticId}";
  resticAwsSecretKeySecret = resticId: "ezfs_restic_aws_secret_key_${resticId}";

  pullSshKey = pushId: "ezfs_pull_backup_ssh_key_${pushId}";

  pushSshKey = pushId: "ezfs_push_backup_ssh_key_${pushId}";

  pullSource = dsCfg: cfg: "${cfg.user}@${cfg.host}:${dsCfg.name}";

  pushTarget = pushCfg: "${pushCfg.user}@${pushCfg.host}:${pushCfg.targetDatasetName}";

in
{
  options.ezfs = {
    enable = lib.mkEnableOption "ezfs ZFS dataset management";
    hosts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            publicKey = lib.mkOption {
              type = lib.types.str;
            };
            privateKey = lib.mkOption {
              type = lib.types.path;
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
            dependsOn = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            snapshots = snapshotsOption {
              default = sanoidDefaultCounts;
              description = "Sanoid's automatic snapshots of this dataset, and how many of each are kept.";
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
                type = lib.types.path;
              };
              snapshots = targetSnapshotsOption;
            };
          }
        )
      );
    };
    push-backups = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }:
          {
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
                type = lib.types.path;
              };
              snapshots = targetSnapshotsOption;
            };
          }
        )
      );
    };
    restic-backups = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }:
          {
            options = {
              enable = lib.mkEnableOption "Enable the restic backup to S3";
              backupService = lib.mkOption {
                type = lib.types.str;
                readOnly = true;
                default = "restic-backup-${config._module.args.name}.service";
              };
              sourceDatasetId = lib.mkOption {
                type = lib.types.str;
                description = "Dataset ID to backup (key in ezfs.datasets)";
              };
              repository = lib.mkOption {
                type = lib.types.str;
                description = "S3 URL (e.g., s3:http://garage:3900/bucket)";
              };
              passwordFile = lib.mkOption {
                type = lib.types.path;
                description = "Agenix secret path for restic repo password";
              };
              awsAccessKeyIdFile = lib.mkOption {
                type = lib.types.path;
                description = "Agenix secret path for AWS_ACCESS_KEY_ID";
              };
              awsSecretAccessKeyFile = lib.mkOption {
                type = lib.types.path;
                description = "Agenix secret path for AWS_SECRET_ACCESS_KEY";
              };
              pruneOpts = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Options for restic forget --prune (e.g., --keep-daily 7)";
              };
              extraBackupArgs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Extra arguments for restic backup";
              };
              exclude = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = "Patterns to exclude from backup";
              };
              timerConfig = lib.mkOption {
                type = lib.types.nullOr (lib.types.attrsOf lib.types.str);
                default = {
                  OnCalendar = "daily";
                };
                description = "Systemd timer config (set to null to disable timer)";
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkMerge [
    {
      assertions =
        let
          hostIds = lib.lists.unique (lib.mapAttrsToList (_dsName: dsCfg: dsCfg.hostId) config.ezfs.datasets);
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
        let
          ed25519Keys = builtins.filter (k: k.type == "ed25519") config.services.openssh.hostKeys;
          paths = builtins.map (k: k.path) ed25519Keys;
          uniquePaths = lib.lists.unique paths;
          pathsStr = builtins.concatStringsSep ", " uniquePaths;
        in
        [
          {
            assertion = builtins.length uniquePaths <= 1;
            message = ''
              Duplicate SSH host key with type ed25519 is found: ${pathsStr}
              SSH doesn't support multiple host keys of the same type
            '';
          }
        ];
    }
    (lib.mkIf config.ezfs.enable {
      systemd.services."ezfs-mount" = {
        description = "Mount and configure ezfs datasets";
        restartIfChanged = true;
        serviceConfig.Type = "oneshot";
        startLimitIntervalSec = 0;
        after = [
          "agenix.service"
          "zfs-mount.service"
        ];
        wants = [
          "agenix.service"
          "zfs-mount.service"
        ];
        wantedBy = [ "multi-user.target" ];
        path = [
          "/run/booted-system/sw/"
          pkgs.jq
        ];
        enableStrictShellChecks = true;
        environment.HOST_ID = config.networking.hostId;
        environment.EZFS_CFG = pkgs.writeText "ezfs.json" (
          builtins.toJSON (
            config.ezfs
            // {
              datasets = lib.filterAttrs (
                _: ds: ds.enable && ds.hostId == config.networking.hostId
              ) config.ezfs.datasets;
            }
          )
        );
        script = builtins.readFile ./ezfs-mount.sh;
      };
    })
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

      age = mapPullTarget (
        { pullId, pullCfg, ... }:
        {
          secrets.${pullSshKey pullId}.file = pullCfg.privateKey;
        }
      );

      systemd = mapPullTarget (
        { pullId, ... }:
        let
          credentialName = pullSshKey pullId;
        in
        {
          services."syncoid-pull-backup-${pullId}" = {
            wants = [
              "agenix.service"
              "zfs-mount.service"
            ];
            after = [
              "agenix.service"
              "zfs-mount.service"
            ];
            serviceConfig.LoadCredential = "${credentialName}:${config.age.secrets.${credentialName}.path}";
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
          # autosnap stays off whatever `snapshots` says: this dataset is
          # written by syncoid, and sanoid's only job here is to expire what
          # arrives. The counts are what `snapshots` decides.
          sanoid.datasets.${pullCfg.targetDatasetName} = {
            autosnap = lib.mkDefault false;
            autoprune = lib.mkDefault true;
          }
          // expandSnapshots pullCfg.snapshots;
          syncoid.enable = true;
          syncoid.commands."pull-backup-${pullId}" = {
            sshKey = "%d/${pullSshKey pullId}";
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
                --sshkey ${config.age.secrets.${pullSshKey pullId}.path} \
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
            # "none" is the one value that has to reach autosnap as well as
            # the counts: taking no snapshots and keeping none are the two
            # halves of the same instruction, and splitting them is exactly
            # the half-state this option exists to make unwritable.
            autosnap = lib.mkDefault (dsCfg.snapshots != "none");
            autoprune = lib.mkDefault true;
          }
          // expandSnapshots dsCfg.snapshots;
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
                type = "ed25519";
                path = config.age.secrets."ezfs_sshd_key".path;
              }
            ];
          };
        }
      );

      age = mapPullSource (
        { ... }:
        {
          secrets."ezfs_sshd_key".file = config.ezfs.hosts.${config.networking.hostId}.privateKey;
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

    }
    (lib.mkIf config.ezfs.enable {
      systemd.services."ezfs-setup-push-backup" = {
        description = "Setup ZFS push backups";
        restartIfChanged = true;
        serviceConfig.Type = "oneshot";
        startLimitIntervalSec = 0;
        after = [
          "agenix.service"
          "zfs-mount.service"
        ];
        wants = [
          "agenix.service"
          "zfs-mount.service"
        ];
        wantedBy = [ "multi-user.target" ];
        path = [
          "/run/booted-system/sw/"
          pkgs.jq
        ];
        enableStrictShellChecks = true;
        environment.PUSH_BACKUPS = pkgs.writeText "push-backups.json" (
          builtins.toJSON (
            lib.mapAttrs (_: cfg: builtins.removeAttrs cfg [ "privateKey" ]) (
              lib.filterAttrs (_: cfg: cfg.enable) config.ezfs.push-backups
            )
          )
        );
        script = builtins.readFile ./ezfs-setup-push-backup.sh;
      };
    })
    {

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
        {
          sanoid.enable = true;
          # autosnap stays off whatever `snapshots` says: this dataset is
          # written by syncoid from the far side, and sanoid's only job here
          # is to expire what arrives. The counts are what `snapshots`
          # decides.
          sanoid.datasets.${pushCfg.targetDatasetName} = {
            autosnap = lib.mkDefault false;
            autoprune = lib.mkDefault true;
          }
          // expandSnapshots pushCfg.snapshots;
          openssh = {
            enable = true;
            allowSFTP = lib.mkDefault false;
            settings = {
              PubkeyAuthentication = true;
              AuthenticationMethods = lib.mkDefault "publickey";
            };
            hostKeys = [
              {
                type = "ed25519";
                path = config.age.secrets."ezfs_sshd_key".path;
              }
            ];
          };
        }
      );

      age = mapPushTarget (
        { ... }:
        {
          secrets."ezfs_sshd_key".file = config.ezfs.hosts.${config.networking.hostId}.privateKey;
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
      age = mapPushSource (
        { pushId, pushCfg, ... }:
        {
          secrets.${pushSshKey pushId}.file = pushCfg.privateKey;
        }
      );

      systemd = mapPushSource (
        { pushId, ... }:
        let
          credentialName = pushSshKey pushId;
        in
        {
          services."syncoid-push-backup-${pushId}" = {
            serviceConfig.LoadCredential = "${credentialName}:${config.age.secrets.${credentialName}.path}";
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
            sshKey = "%d/${pushSshKey pushId}";
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
                --sshkey ${config.age.secrets.${pushSshKey pushId}.path} \
                --sshoption='StrictHostKeyChecking=yes' \
                --sshoption='UserKnownHostsFile=${pushKnownHost pushCfg}' \
                --no-sync-snap \
                --no-privilege-elevation \
                --sendoptions="w" \
                --recvoptions="u" \
                ${pushTarget pushCfg} \
                ${dsCfg.name}
              '';
            })
          ];
        }
      );
    }
    {
      # syncoid runs with --no-sync-snap, so replication only ever sends
      # snapshots sanoid already took on the source. `snapshots = "none"` --
      # and equally an attribute set that leaves every keep count at 0 --
      # means none is ever taken, so the syncoid unit has nothing to send and
      # fails on every run. That is the same silent pairing the restic
      # assertion below catches, one path over.
      #
      # The guard mirrors mapPullSource/mapPushSource exactly, which is to say
      # it deliberately does *not* look at the backup's own `enable`. By this
      # module's convention `enable` is set on the host that owns the target
      # dataset, never on the source: the source-side plumbing -- including
      # the push-backup's own syncoid unit, built by mapPushSource -- is
      # generated whenever the source dataset is enabled and local. Adding
      # `enable` here would make this assertion unreachable, since no host
      # satisfies both `enable` and `hostId == dsCfg.hostId`.
      assertions =
        let
          sourceAssertion =
            kind: backupId: backupCfg:
            let
              dsCfg = config.ezfs.datasets.${backupCfg.sourceDatasetId};
            in
            {
              assertion =
                !(config.ezfs.enable && dsCfg.enable && config.networking.hostId == dsCfg.hostId)
                || takesSnapshots dsCfg.snapshots;
              message = ''
                ezfs.${kind}.${backupId} replicates dataset ${backupCfg.sourceDatasetId} with
                syncoid --no-sync-snap, which only sends snapshots that already exist, but that
                dataset keeps no snapshots (snapshots = "none", or every keep count 0), so sanoid
                never takes one and there is nothing to replicate.
              '';
            };
        in
        lib.mapAttrsToList (sourceAssertion "pull-backups") config.ezfs.pull-backups
        ++ lib.mapAttrsToList (sourceAssertion "push-backups") config.ezfs.push-backups;
    }
    {
      # ezfs-restic-backup.sh backs up the newest `autosnap` snapshot of the
      # source dataset and exits 1 when there is none. Sanoid only snapshots a
      # type whose keep count is above 0, so `snapshots = "none"` -- and
      # equally an attribute set that leaves every count at 0 -- means no
      # autosnap snapshot ever exists. The pairing is a config error that
      # would otherwise only show up as a failing timer.
      #
      # The guard mirrors mapResticBackup's exactly, so the assertion fires on
      # precisely the hosts that get a backup unit: not on a host that merely
      # sees the same shared `ezfs` config but runs the dataset elsewhere, and
      # not when the backup itself is disabled.
      assertions = lib.mapAttrsToList (
        resticId: resticCfg:
        let
          dsCfg = config.ezfs.datasets.${resticCfg.sourceDatasetId};
        in
        {
          assertion =
            !(config.ezfs.enable && resticCfg.enable && config.networking.hostId == dsCfg.hostId)
            || takesSnapshots dsCfg.snapshots;
          message = ''
            ezfs.restic-backups.${resticId} backs up the newest sanoid autosnap snapshot of
            dataset ${resticCfg.sourceDatasetId}, but that dataset keeps no snapshots
            (snapshots = "none", or every keep count 0), so no autosnap snapshot is ever
            taken and the backup fails on every run.
          '';
        }
      ) config.ezfs.restic-backups;

      age = mapResticBackup (
        { resticId, resticCfg, ... }:
        {
          secrets.${resticPasswordSecret resticId}.file = resticCfg.passwordFile;
          secrets.${resticAwsAccessKeySecret resticId}.file = resticCfg.awsAccessKeyIdFile;
          secrets.${resticAwsSecretKeySecret resticId}.file = resticCfg.awsSecretAccessKeyFile;
        }
      );

      systemd.services = mapResticBackup (
        {
          resticId,
          resticCfg,
          dsCfg,
          ...
        }:
        {
          "restic-backup-${resticId}" = {
            description = "Restic backup for ${dsCfg.name} to S3";
            restartIfChanged = false;
            wants = [
              "agenix.service"
              "zfs-mount.service"
              "ezfs-mount.service"
              "network-online.target"
            ];
            after = [
              "agenix.service"
              "zfs-mount.service"
              "ezfs-mount.service"
              "network-online.target"
            ];
            path = [
              "/run/booted-system/sw"
              pkgs.restic
            ];
            environment = {
              RESTIC_REPOSITORY = resticCfg.repository;
              DATASET = dsCfg.name;
              MOUNTPOINT = dsCfg.options.mountpoint or "/${dsCfg.name}";
              STABLE_PATH = resticStablePath resticId;
              # Without this restic has neither $HOME nor $XDG_CACHE_HOME and
              # runs cacheless, warning "running prune without a cache, this
              # may be very slow" and re-fetching every tree blob from the
              # remote on each run.
              RESTIC_CACHE_DIR = "/var/cache/${resticCacheDir resticId}";
              EXTRA_BACKUP_ARGS = lib.concatStringsSep " " (
                resticCfg.extraBackupArgs ++ (map (p: "--exclude=${p}") resticCfg.exclude)
              );
              PRUNE_OPTS = lib.concatStringsSep " " resticCfg.pruneOpts;
            };
            serviceConfig = {
              Type = "oneshot";
              CacheDirectory = resticCacheDir resticId;
              LoadCredential = [
                "password:${config.age.secrets.${resticPasswordSecret resticId}.path}"
                "aws_access_key:${config.age.secrets.${resticAwsAccessKeySecret resticId}.path}"
                "aws_secret_key:${config.age.secrets.${resticAwsSecretKeySecret resticId}.path}"
              ];
            };
            enableStrictShellChecks = true;
            script = builtins.readFile ./ezfs-restic-backup.sh;
          };
        }
      );

      systemd.timers = mapResticBackup (
        { resticId, resticCfg, ... }:
        lib.mkIf (resticCfg.timerConfig != null) {
          "restic-backup-${resticId}" = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              Persistent = true;
            }
            // resticCfg.timerConfig;
          };
        }
      );

      environment = mapResticBackup (
        {
          dsCfg,
          resticId,
          resticCfg,
          ...
        }:
        {
          systemPackages = [
            (pkgs.writeShellApplication {
              name = "ezfs-prepare-restore-restic-backup-${resticId}";
              runtimeInputs = [ "/run/booted-system/sw" ];
              text = ''
                # Recreate the ZFS dataset if destroyed
                if ! zfs list -H "${dsCfg.name}"; then
                  zfs create -u ${
                    lib.concatStringsSep " " (lib.mapAttrsToList (n: v: "-o ${n}=${v}") dsCfg.options)
                  } ${dsCfg.name}
                fi

                # Mount the dataset
                mounted=$(zfs get -H -o value mounted "${dsCfg.name}")
                if [ "$mounted" != "yes" ]; then
                  zfs mount "${dsCfg.name}"
                fi

                # Set ownership
                mountpoint=$(zfs get -H -o value mountpoint "${dsCfg.name}")
                chown "${dsCfg.user}":"${dsCfg.group}" "$mountpoint"
              '';
            })

            (pkgs.writeShellApplication {
              name = "ezfs-restore-restic-backup-${resticId}";
              runtimeInputs = [
                "/run/booted-system/sw"
                pkgs.restic
              ];
              text = ''
                # Load credentials from agenix secrets
                export RESTIC_PASSWORD
                RESTIC_PASSWORD=$(cat "${config.age.secrets.${resticPasswordSecret resticId}.path}")
                export AWS_ACCESS_KEY_ID
                AWS_ACCESS_KEY_ID=$(cat "${config.age.secrets.${resticAwsAccessKeySecret resticId}.path}")
                export AWS_SECRET_ACCESS_KEY
                AWS_SECRET_ACCESS_KEY=$(cat "${config.age.secrets.${resticAwsSecretKeySecret resticId}.path}")
                export RESTIC_REPOSITORY="${resticCfg.repository}"

                mountpoint=$(zfs get -H -o value mountpoint "${dsCfg.name}")

                # Restore files from restic into the mounted dataset
                # --target is where files are restored; restic restores the full path structure
                # So if backup was from /spool/foo/.zfs/snapshot/X, we restore to / and files go to /spool/foo/.zfs/snapshot/X
                # Instead, we want files at mountpoint, so we use a temp dir and move
                tmpdir=$(mktemp -d)
                restic restore latest --target "$tmpdir"

                # Backups now run from a fixed bind-mount path, so the restored
                # tree is just tmpdir + that path.
                snapshot_dir="$tmpdir${resticStablePath resticId}"

                # Snapshots taken before that change recorded the ZFS snapshot
                # directory instead, nested under .zfs/snapshot/<name>/ five
                # levels deep, e.g. tmpdir/spool/foo/.zfs/snapshot/autosnap_...
                if [ ! -d "$snapshot_dir" ]; then
                  snapshot_dir=$(find "$tmpdir" -mindepth 5 -maxdepth 5 -type d -path "*/.zfs/snapshot/*" | head -1)
                fi

                if [ -n "$snapshot_dir" ] && [ -d "$snapshot_dir" ]; then
                  # Move contents to mountpoint
                  cp -a "$snapshot_dir"/. "$mountpoint"/
                fi

                rm -rf "$tmpdir"
              '';
            })
          ];
        }
      );
    }
  ];
}
