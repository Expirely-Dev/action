#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

input_default=$(awk '/^  version:$/ { in_version = 1; next } in_version && /^    default:/ { gsub(/[\047" ]/, "", $2); print $2; exit }' action.yml)
env_default=$(sed -n "s/^        EXPIRELY_DEFAULT_VERSION: '\\(.*\\)'\$/\\1/p" action.yml)
vendored=$(find versions -name '*.sha256' -exec basename {} .sha256 \;)

status=0
if [[ -z "$input_default" || "$input_default" != "$env_default" ]]; then
  echo "action.yml: inputs.version.default is \"${input_default}\" but EXPIRELY_DEFAULT_VERSION is \"${env_default}\"" >&2
  status=1
fi
if [[ "$vendored" != "$input_default" ]]; then
  echo "versions/ holds \"${vendored//$'\n'/, }\" but the default version is \"${input_default}\"; keep exactly versions/${input_default}.sha256" >&2
  status=1
fi
if [[ -f "versions/${input_default}.sha256" ]]; then
  for platform in darwin_amd64.tar.gz darwin_arm64.tar.gz linux_amd64.tar.gz linux_arm64.tar.gz windows_amd64.zip windows_arm64.zip; do
    if ! grep -Eq "^[0-9a-f]{64}  expirely_${input_default}_${platform}\$" "versions/${input_default}.sha256"; then
      echo "versions/${input_default}.sha256 has no checksum for expirely_${input_default}_${platform}" >&2
      status=1
    fi
  done
fi
if ((status == 0)); then
  echo "default version ${input_default}: action.yml and versions/ agree"
fi
exit "$status"
