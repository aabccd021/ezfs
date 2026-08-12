set -x

# Read credentials from systemd's CREDENTIALS_DIRECTORY
export RESTIC_PASSWORD
RESTIC_PASSWORD=$(cat "$CREDENTIALS_DIRECTORY/password")
export AWS_ACCESS_KEY_ID
AWS_ACCESS_KEY_ID=$(cat "$CREDENTIALS_DIRECTORY/aws_access_key")
export AWS_SECRET_ACCESS_KEY
AWS_SECRET_ACCESS_KEY=$(cat "$CREDENTIALS_DIRECTORY/aws_secret_key")

# Find latest sanoid autosnap snapshot
snapshot=$(zfs list -t snapshot -o name -s creation -H "$DATASET" | grep 'autosnap' | tail -1)

if [ -z "$snapshot" ]; then
  echo "No autosnap snapshot found for $DATASET"
  exit 1
fi

# Extract snapshot name (part after @)
snapshot_name=${snapshot#*@}

# Access snapshot via .zfs/snapshot/<name>/ (no explicit mount needed)
snapshot_path="$MOUNTPOINT/.zfs/snapshot/$snapshot_name"

if [ ! -d "$snapshot_path" ]; then
  echo "Snapshot path $snapshot_path does not exist"
  exit 1
fi

# Trigger ZFS snapshot automount by listing the directory contents.
# The [ -d ] check above uses stat() which confirms the directory exists but
# may not trigger content materialization on some ZFS/kernel versions.
ls "$snapshot_path"

# restic decides whether a file changed by looking it up at the same path in
# the parent snapshot. $snapshot_path ends in the sanoid snapshot name, which
# is different on every run, so no file ever matched and each run re-read the
# whole dataset from disk — 300 GiB of reads to upload a few MiB. The same
# moving path also put every snapshot in its own forget/prune group, so
# retention policies silently kept everything.
#
# Bind-mounting onto a fixed path makes the tree restic sees identical between
# runs, which restores both parent matching and retention grouping.
mkdir -p "$STABLE_PATH"

# A run killed mid-flight leaves the bind mount behind; stacking another on top
# would hide it and leak mounts until reboot.
if findmnt --mountpoint "$STABLE_PATH" >/dev/null; then
  umount "$STABLE_PATH"
fi

mount --bind "$snapshot_path" "$STABLE_PATH"
trap 'umount "$STABLE_PATH"' EXIT

# Initialize repo if needed (idempotent — exits 0 if already initialized)
restic init || true

# Run backup from the stable path
# shellcheck disable=SC2086
restic backup "$STABLE_PATH" $EXTRA_BACKUP_ARGS

# Prune if configured
if [ -n "$PRUNE_OPTS" ]; then
  # shellcheck disable=SC2086
  restic forget --prune $PRUNE_OPTS
fi
