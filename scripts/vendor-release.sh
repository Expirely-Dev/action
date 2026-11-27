#!/usr/bin/env bash
set -euo pipefail

usage="usage: scripts/vendor-release.sh vX.Y.Z

Downloads every archive of that bycavii/expirely-cli release and its
checksums.txt, checks each archive against checksums.txt and with
gh attestation verify, then makes it the default version of the action:
versions/X.Y.Z.sha256 replaces the old checksums and action.yml points at it.
Needs gh with a token (GH_TOKEN or gh auth login)."

readonly repo="bycavii/expirely-cli"
readonly signer="bycavii/expirely-cli/.github/workflows/release.yml"

tag=${1:-}
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "$usage" >&2
  exit 2
fi
version=${tag#v}

cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

gh release download "$tag" --repo "$repo" --dir "$work" \
  --pattern checksums.txt --pattern "expirely_${version}_*"

for archive in "$work"/expirely_"${version}"_*; do
  gh attestation verify "$archive" --repo "$repo" --signer-workflow "$signer" \
    --source-ref refs/heads/main --deny-self-hosted-runners >/dev/null
  echo "provenance verified: $(basename "$archive")"
done
(
  cd "$work"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum --check --strict checksums.txt
  else
    shasum -a 256 --check checksums.txt
  fi
)

rm -f versions/*.sha256
cp "$work/checksums.txt" "versions/${version}.sha256"

sed -i.bak "/^  version:\$/,/^    default:/ s/^    default: '.*'\$/    default: '${version}'/" action.yml
rm -f action.yml.bak

echo "default version: $(scripts/check-default-version.sh)"
