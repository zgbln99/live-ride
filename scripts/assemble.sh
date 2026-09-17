#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/open-wanderer/wanderer.git}"
UPSTREAM_REF="$(tr -d '[:space:]' < "$ROOT/UPSTREAM_REF")"
PATCH_SHA="$(tr -d '[:space:]' < "$ROOT/PATCH_SHA256")"
DEST="${1:-$ROOT/.work/assembled}"

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"

# Use a complete clone. The previous blob-filtered clone passed all builds but
# failed when CI tried to push the assembled branch because Git could not
# materialize a promised upstream object from the source remote.
git clone --no-checkout "$UPSTREAM_REPO" "$DEST"
git -C "$DEST" fetch origin feature/app
git -C "$DEST" checkout --detach "$UPSTREAM_REF"

BASE_PATCH="$DEST/.live-ride.patch"
base64 -d "$ROOT/patches/live-ride.patch.gz.b64" | gzip -dc > "$BASE_PATCH"
ACTUAL_SHA="$(sha256sum "$BASE_PATCH" | awk '{print $1}')"
if [[ "$ACTUAL_SHA" != "$PATCH_SHA" ]]; then
  echo "Base patch checksum mismatch: got $ACTUAL_SHA, expected $PATCH_SHA" >&2
  exit 1
fi

git -C "$DEST" apply --check "$BASE_PATCH"
git -C "$DEST" apply "$BASE_PATCH"
rm -f "$BASE_PATCH"

shopt -s nullglob
for patch in "$ROOT"/patches/post/*.patch; do
  echo "Applying $(basename "$patch")"
  git -C "$DEST" apply --check "$patch"
  git -C "$DEST" apply "$patch"
done

git -C "$DEST" diff --check

echo "Live Ride assembled successfully"
echo "Upstream: $UPSTREAM_REF"
echo "Working tree: $DEST"
