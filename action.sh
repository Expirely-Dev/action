#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "::error title=expirely-action::$1"
  exit 1
}

path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath "$1" "$2"; else printf '%s' "$2"; fi
}

version=${EXPIRELY_VERSION#v}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version is \"${EXPIRELY_VERSION}\"; use a release such as 0.6.0."

case "${RUNNER_OS:-}-${RUNNER_ARCH:-}" in
  Linux-X64) platform=linux_amd64.tar.gz ;;
  Linux-ARM64) platform=linux_arm64.tar.gz ;;
  macOS-X64) platform=darwin_amd64.tar.gz ;;
  macOS-ARM64) platform=darwin_arm64.tar.gz ;;
  Windows-X64) platform=windows_amd64.zip ;;
  Windows-ARM64) platform=windows_arm64.zip ;;
  *) fail "expirely has no release for ${RUNNER_OS:-this OS} on ${RUNNER_ARCH:-this architecture}." ;;
esac

archive="expirely_${version}_${platform}"
url="https://github.com/expirely-dev/expirely-cli/releases/download/v${version}"
dir=$(mktemp -d "$(path -u "$RUNNER_TEMP")/expirely.XXXXXXXX")

checksums="$(path -u "$GITHUB_ACTION_PATH")/versions/${version}.sha256"
if [[ ! -f "$checksums" ]]; then
  checksums="${dir}/checksums.txt"
  curl --fail --silent --show-error --location --retry 5 --output "$checksums" "${url}/checksums.txt" ||
    fail "expirely v${version} has no checksums.txt; see https://github.com/expirely-dev/expirely-cli/releases for the versions there are."
fi
curl --fail --silent --show-error --location --retry 5 --output "${dir}/${archive}" "${url}/${archive}" ||
  fail "could not download ${archive}; rerun the job."

expected=$(awk -v f="$archive" '$2 == f { print $1 }' "$checksums")
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "${dir}/${archive}" | awk '{ print $1 }')
else
  actual=$(shasum -a 256 "${dir}/${archive}" | awk '{ print $1 }')
fi
[[ -n "$expected" && "$actual" == "$expected" ]] ||
  fail "${archive} has SHA-256 ${actual}, not ${expected:-a listed checksum}; it was not run."

if [[ "$platform" == *.zip ]]; then
  unzip -q -o "${dir}/${archive}" expirely.exe -d "$dir"
else
  tar -xzf "${dir}/${archive}" -C "$dir" expirely
fi
rm -f "${dir}/${archive}"
printf '%s\n' "$(path -w "$dir")" >>"$GITHUB_PATH"
echo "Installed expirely ${version}, SHA-256 verified."

trim() {
  local s=${1%$'\r'}
  s=${s#"${s%%[![:space:]]*}"}
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}

run_args=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line=$(trim "$line")
  if [[ -n "$line" ]]; then
    run_args+=("$line")
  fi
done <<<"${EXPIRELY_ARGS:-}"
targets=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line=$(trim "$line")
  if [[ -n "$line" && "$line" != \#* ]]; then
    targets+=("$line")
  fi
done <<<"${EXPIRELY_TARGETS:-}"

if ((${#run_args[@]} + ${#targets[@]} == 0)); then
  exit 0
fi
if ((${#targets[@]} > 0)); then
  run_args+=(-- "${targets[@]}")
fi
exec "${dir}/expirely" "${run_args[@]}"
