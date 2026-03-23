set -x

# Options that can only be set at creation time (not updateable)
CREATE_ONLY_OPTIONS='["encryption", "casesensitivity", "utf8only", "normalization", "volblocksize", "pbkdf2iters", "pbkdf2salt", "keyformat"]'

# Get dataset IDs for this host, sorted by mountpoint depth (shallower first)
# Use mountpoint from options if set, otherwise use dataset name as fallback
dsIds=$(jq -r --arg hostId "$HOST_ID" '
  .datasets | to_entries[]
  | select(.value.enable and .value.hostId == $hostId)
  | ((.value.options.mountpoint // ("/" + .value.name)) | split("/") | length) as $depth
  | [$depth, .key]
  | @tsv
' "$EZFS_CFG" | sort -n | cut -f2 | tr '\n' ' ')

for dsId in $dsIds; do
  dataset=$(jq -r --arg dsId "$dsId" '.datasets[$dsId].name' "$EZFS_CFG")
  user=$(jq -r --arg dsId "$dsId" '.datasets[$dsId].user' "$EZFS_CFG")
  group=$(jq -r --arg dsId "$dsId" '.datasets[$dsId].group' "$EZFS_CFG")
  pool=$(echo "$dataset" | cut -d'/' -f1)

  # Get backup users for this dataset
  backupUsers=$(jq -r --arg dsId "$dsId" '
    ."pull-backups" | to_entries[]
    | select(.value.sourceDatasetId == $dsId)
    | .value.user
  ' "$EZFS_CFG" | sort -u | tr '\n' ' ')

  # Unallow backup users from pool
  for backupUser in $backupUsers; do
    zfs unallow -u "$backupUser" "$pool"
  done

  # Get updateable ZFS options (exclude create-only options)
  updateOptions=$(jq -r --arg dsId "$dsId" --argjson exclude "$CREATE_ONLY_OPTIONS" '
    .datasets[$dsId].options | to_entries[]
    | select(.key as $k | $exclude | index($k) | not)
    | "\(.key)=\(.value)"
  ' "$EZFS_CFG" | tr '\n' ' ')

  # Set updateable ZFS options
  for opt in $updateOptions; do
    name="${opt%%=*}"
    value="${opt#*=}"
    if [ "$(zfs get -H -o value "$name" "$dataset")" != "$value" ]; then
      zfs set "$name=$value" "$dataset"
    fi
  done

  # Load encryption key if needed
  encryption=$(zfs get -H -o value encryption "$dataset")
  if [ "$encryption" != "off" ]; then
    keystatus=$(zfs get -H -o value keystatus "$dataset")
    if [ "$keystatus" != "available" ]; then
      zfs load-key "$dataset"
    fi
  fi

  # Mount if not mounted
  mounted=$(zfs get -H -o value mounted "$dataset")
  if [ "$mounted" != "yes" ]; then
    zfs mount "$dataset"
  fi

  # Set ownership on mountpoint
  mountpoint=$(zfs get -H -o value mountpoint "$dataset")
  if [ -d "$mountpoint" ]; then
    chown "$user":"$group" "$mountpoint"
  fi

  # Unallow user from dataset
  zfs unallow -u "$user" "$dataset"

  # Set user allows for backup users (send, hold, bookmark permissions)
  for allowUser in $backupUsers; do
    zfs allow -u "$allowUser" send,hold,bookmark "$dataset"
  done

done
