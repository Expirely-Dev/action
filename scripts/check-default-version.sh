#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

default=$(awk '/^  version:$/ { found = 1; next } found && /^    default:/ { gsub(/[\047" ]/, "", $2); print $2; exit }' action.yml)
vendored=$(find versions -name '*.sha256' -exec basename {} .sha256 \;)

if [[ -z "$default" || "$vendored" != "$default" ]]; then
  echo "versions/ holds \"${vendored//$'\n'/, }\" but inputs.version.default is \"${default}\"; keep exactly versions/${default}.sha256" >&2
  exit 1
fi
for platform in darwin_amd64.tar.gz darwin_arm64.tar.gz linux_amd64.tar.gz linux_arm64.tar.gz windows_amd64.zip windows_arm64.zip; do
  if ! grep -Eq "^[0-9a-f]{64}  expirely_${default}_${platform}\$" "versions/${default}.sha256"; then
    echo "versions/${default}.sha256 has no checksum for expirely_${default}_${platform}" >&2
    exit 1
  fi
done
echo "${default}"
