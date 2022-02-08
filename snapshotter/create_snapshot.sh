#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

export PATH=$PATH:/usr/bin:/snap/bin

if [ "$PRODUCTION" == "1" ]; then
    SNAPSHOT_BUCKET='helium-snapshots.nebra.com'
else
    SNAPSHOT_BUCKET='helium-snapshots-stage.nebra.com'
fi

docker exec miner miner snapshot take /var/data/saved-snaps/latest
BLOCK_HEIGHT=$(docker exec miner miner snapshot info /var/data/saved-snaps/latest | head -1 | awk {'print $2'})
BLOCK_HASH_PART1=$(docker exec miner miner snapshot info /var/data/saved-snaps/latest | tail -3 | head -1 | awk {'print $2'})
BLOCK_HASH_PART2=$(docker exec miner miner snapshot info /var/data/saved-snaps/latest | tail -2 | head -1 | awk {'print $1'})
BYTE_ARRAY="${BLOCK_HASH_PART1}${BLOCK_HASH_PART2}"
BASE64URL_FORMAT=$(python3 /home/snapshot/hm-block-tracker/snapshotter/base64url_encoder.py "$BYTE_ARRAY")
TMPDIR=$(mktemp -d)

mv /var/miner_data/saved-snaps/latest "$TMPDIR/snap-$BLOCK_HEIGHT"
echo "{\"height\": $BLOCK_HEIGHT, \"hash\": \"$BYTE_ARRAY\"}" | tee -a "$TMPDIR/latest.json"
echo "{\"height\": $BLOCK_HEIGHT, \"hash\": \"$BASE64URL_FORMAT\"}" | tee -a "$TMPDIR/latest-snap.json"

# Ensure neither snaphot 'height' nor 'hash' are empty.
are_snapshots_valid=1
for file in $TMPDIR/{latest.json,latest-snap.json}; do
    sanity_check=$(jq '.[] | select(. == null or . == "")' < "$file")
    if [ -n "$sanity_check" ]; then
        echo "'hash' or 'height' returned empty in $file. Will not upload snapshots."
        are_snapshots_valid=0
    fi
done

# Only upload snapshots if they are all valid.
if [ "$are_snapshots_valid" -eq "1" ]; then
    gsutil cp "$TMPDIR/snap-$BLOCK_HEIGHT" "gs://$SNAPSHOT_BUCKET/snap-$BLOCK_HEIGHT"
    gsutil cp "$TMPDIR/latest.json" "gs://$SNAPSHOT_BUCKET/latest.json"
    gsutil cp "$TMPDIR/latest-snap.json" "gs://$SNAPSHOT_BUCKET/latest-snap.json"
fi

rm -rf "$TMPDIR" docker.config
