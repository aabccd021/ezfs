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

# Initialize repo if needed
if ! restic snapshots >/dev/null 2>&1; then
  echo "Initializing restic repository..."
  restic init
fi

# Run backup from snapshot path
# shellcheck disable=SC2086
restic backup "$snapshot_path" $EXTRA_BACKUP_ARGS

# Prune if configured
if [ -n "$PRUNE_OPTS" ]; then
  # shellcheck disable=SC2086
  restic forget --prune $PRUNE_OPTS
fi
