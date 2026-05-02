set -x

# Get all push backup IDs
pushIds=$(jq -r 'keys[]' "$PUSH_BACKUPS" | tr '\n' ' ')

for pushId in $pushIds; do
  dataset=$(jq -r --arg id "$pushId" '.[$id].targetDatasetName' "$PUSH_BACKUPS")
  user=$(jq -r --arg id "$pushId" '.[$id].user' "$PUSH_BACKUPS")
  pool=$(echo "$dataset" | cut -d'/' -f1)

  zfs unallow -u "$user" "$pool"
  zfs allow -u "$user" create,receive,mount "$pool"

  # if dataset already exists, we need to set the options
  if zfs list -H "$dataset"; then
    zfs allow -u "$user" canmount,mountpoint,keylocation "$dataset"
  fi
done
