set -x

# Read dataset config
dataset=$(jq -r '.name' "$DS_CFG")
user=$(jq -r '.user' "$DS_CFG")
group=$(jq -r '.group' "$DS_CFG")
pool=$(echo "$dataset" | cut -d'/' -f1)

# Options that can only be set at creation time (not updateable)
CREATE_ONLY_OPTIONS='["encryption", "casesensitivity", "utf8only", "normalization", "volblocksize", "pbkdf2iters", "pbkdf2salt", "keyformat"]'

# Unallow backup users from pool
jq -r --arg dsId "$DS_ID" '.[] | select(.sourceDatasetId == $dsId) | .user' "$PULL_BACKUPS" | sort -u | while read -r backupUser; do
  zfs unallow -u "$backupUser" "$pool"
done

# Set updateable ZFS options (exclude create-only options)
jq -r --argjson exclude "$CREATE_ONLY_OPTIONS" '.options | to_entries[] | select(.key as $k | $exclude | index($k) | not) | "\(.key) \(.value)"' "$DS_CFG" | while read -r name value; do
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

# Mount all available datasets in mountpoint depth order
zfs mount -a

# Set ownership on mountpoint
mountpoint=$(zfs get -H -o value mountpoint "$dataset")
if [ -d "$mountpoint" ]; then
  chown "$user":"$group" "$mountpoint"
fi

# Unallow user from dataset
zfs unallow -u "$user" "$dataset"

# Set user allows for backup users (send, hold, bookmark permissions)
jq -r --arg dsId "$DS_ID" '.[] | select(.sourceDatasetId == $dsId) | .user' "$PULL_BACKUPS" | sort -u | while read -r allowUser; do
  zfs allow -u "$allowUser" send,hold,bookmark "$dataset"
done
