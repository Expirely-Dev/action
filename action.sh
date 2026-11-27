#!/usr/bin/env bash
set -euo pipefail

readonly repo="bycavii/expirely-cli"
readonly signer="bycavii/expirely-cli/.github/workflows/release.yml"
readonly minimum_version="0.6.0"
readonly max_rows=200
readonly max_annotations=10

escape_data() {
  local s=$1
  s=${s//'%'/'%25'}
  s=${s//$'\r'/'%0D'}
  s=${s//$'\n'/'%0A'}
  printf '%s' "$s"
}

escape_property() {
  local s
  s=$(escape_data "$1")
  s=${s//':'/'%3A'}
  s=${s//','/'%2C'}
  printf '%s' "$s"
}

fail() {
  local code=$1 message=$2 fix=$3
  echo "::error title=$(escape_property "expirely-action: ${code}")::$(escape_data "${message} ${fix}")"
  exit 1
}

parse_bool() {
  local name=$1 value=$2 var=$3
  case "$value" in
    true | True | TRUE) printf -v "$var" '%s' true ;;
    false | False | FALSE) printf -v "$var" '%s' false ;;
    *) fail invalid_input "${name} is \"${value}\"." "Use true or false." ;;
  esac
}

trim() {
  local s=${1%$'\r'}
  s=${s#"${s%%[![:space:]]*}"}
  s=${s%"${s##*[![:space:]]}"}
  printf '%s' "$s"
}

unix_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi
}

native_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail missing_tool "$1 is not installed on this runner." "$2"
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

version_at_least() {
  local -a have want
  local i
  IFS=. read -r -a have <<<"$1"
  IFS=. read -r -a want <<<"$2"
  for i in 0 1 2; do
    ((10#${have[i]} > 10#${want[i]})) && return 0
    ((10#${have[i]} < 10#${want[i]})) && return 1
  done
  return 0
}

download() {
  local url=$1 out=$2 status
  status=$(curl --silent --show-error --location --retry 5 --retry-delay 2 --connect-timeout 20 \
    --output "$out" --write-out '%{http_code}' "$url") || status=000
  printf '%s' "$status"
}

set_output() {
  local value=${2//$'\n'/ }
  printf '%s=%s\n' "$1" "${value//$'\r'/}" >>"$GITHUB_OUTPUT"
}

want_summary=""
want_annotations=""
fail_on_error=""
install_only=""
parse_bool summary "${EXPIRELY_SUMMARY:-true}" want_summary
parse_bool annotations "${EXPIRELY_ANNOTATIONS:-true}" want_annotations
parse_bool fail-on-error "${EXPIRELY_FAIL_ON_ERROR:-true}" fail_on_error
parse_bool install-only "${EXPIRELY_INSTALL_ONLY:-false}" install_only

fail_on=${EXPIRELY_FAIL_ON:-expiring}
case "$fail_on" in
  expiring | expired | never) ;;
  *) fail invalid_input "fail-on is \"${fail_on}\"." "Use expiring, expired or never." ;;
esac

verify_mode=${EXPIRELY_VERIFY_ATTESTATION:-auto}
case "$verify_mode" in
  auto | true | false) ;;
  *) fail invalid_input "verify-attestation is \"${verify_mode}\"." "Use auto, true or false." ;;
esac

warn_days=$(trim "${EXPIRELY_WARN_DAYS:-}")
if [[ -n "$warn_days" && ! "$warn_days" =~ ^[0-9]+$ ]]; then
  fail invalid_input "warn-days is \"${warn_days}\"." "Use a whole number of days such as 21, or leave it empty for 30."
fi

default_version=${EXPIRELY_DEFAULT_VERSION:?}
version=$(trim "${EXPIRELY_VERSION:-$default_version}")
version=${version#v}
if [[ "$version" != latest && ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail invalid_input "version is \"${EXPIRELY_VERSION}\"." "Use a release such as ${default_version} or v${default_version}, or latest."
fi

targets=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line=$(trim "$line")
  [[ -z "$line" || "$line" == \#* ]] && continue
  targets+=("$line")
done <<<"${EXPIRELY_TARGETS:-}"

extra_args=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line=$(trim "$line")
  [[ -z "$line" ]] && continue
  extra_args+=("$line")
done <<<"${EXPIRELY_ARGS:-}"

targets_file=$(trim "${EXPIRELY_TARGETS_FILE:-}")
working_directory=${EXPIRELY_WORKING_DIRECTORY:-.}

if [[ "$install_only" == false && ${#targets[@]} -eq 0 && -z "$targets_file" && ${#extra_args[@]} -eq 0 ]]; then
  fail no_targets "There is nothing to check." "Set targets, targets-file, or args such as aws, or set install-only: true."
fi
if [[ "$install_only" == false && ! -d "$working_directory" ]]; then
  fail invalid_input "working-directory \"${working_directory}\" does not exist." "Check out the repository first, or fix the path."
fi

case "${RUNNER_OS:-}" in
  Linux) os=linux ;;
  macOS) os=darwin ;;
  Windows) os=windows ;;
  *) fail unsupported_platform "The runner OS is \"${RUNNER_OS:-unknown}\"." "expirely ships for Linux, macOS and Windows." ;;
esac
case "${RUNNER_ARCH:-}" in
  X64) arch=amd64 ;;
  ARM64) arch=arm64 ;;
  *) fail unsupported_platform "The runner architecture is \"${RUNNER_ARCH:-unknown}\"." "expirely ships for X64 and ARM64." ;;
esac
ext=tar.gz
exe=expirely
if [[ "$os" == windows ]]; then
  ext=zip
  exe=expirely.exe
fi

need curl "Install curl on the runner, or use a GitHub-hosted runner."
if [[ "$install_only" == false || "$version" == latest ]]; then
  need jq "Install jq on the runner, or use a GitHub-hosted runner, which ships it."
fi

temp_root=$(unix_path "${RUNNER_TEMP:-${TMPDIR:-/tmp}}")
cache_root=$(unix_path "${RUNNER_TOOL_CACHE:-${temp_root}/tool-cache}")
action_path=$(unix_path "${GITHUB_ACTION_PATH:?}")
work=$(mktemp -d "${temp_root}/expirely.XXXXXXXX")

if [[ "$version" == latest ]]; then
  release_json="${work}/release.json"
  if [[ -n "${GH_TOKEN:-}" ]]; then
    status=$(printf 'header = "Authorization: Bearer %s"\n' "$GH_TOKEN" |
      curl --config - --silent --show-error --location --retry 3 --output "$release_json" --write-out '%{http_code}' \
        "https://api.github.com/repos/${repo}/releases/latest") || status=000
  else
    status=$(download "https://api.github.com/repos/${repo}/releases/latest" "$release_json")
  fi
  if [[ "$status" != 200 ]]; then
    fail version_not_found "Resolving the latest expirely release failed with HTTP ${status}." "Pin version to a release such as ${default_version}, or pass a token to raise the API rate limit."
  fi
  version=$(jq -r '.tag_name // empty' "$release_json")
  version=${version#v}
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail version_not_found "The latest expirely release has no version tag." "Pin version to a release such as ${default_version}."
fi

if ! version_at_least "$version" "$minimum_version"; then
  fail invalid_input "version ${version} is older than ${minimum_version}, the first release this action supports." "Use ${minimum_version} or newer, or leave version at its default."
fi

archive="expirely_${version}_${os}_${arch}.${ext}"
base_url="https://github.com/${repo}/releases/download/v${version}"

if [[ "$version" == "$default_version" ]]; then
  checksums="${action_path}/versions/${version}.sha256"
  [[ -f "$checksums" ]] || fail checksum_mismatch "This action has no checksums for its default version ${version}." "Report it at https://github.com/bycavii/expirely-action/issues."
else
  checksums="${work}/checksums.txt"
  status=$(download "${base_url}/checksums.txt" "$checksums")
  case "$status" in
    200) ;;
    404) fail version_not_found "expirely v${version} has no release." "See https://github.com/${repo}/releases for the versions there are." ;;
    *) fail download_failed "Downloading checksums.txt of v${version} failed with HTTP ${status}." "Rerun the job; GitHub release downloads fail now and then." ;;
  esac
fi
expected=$(awk -v f="$archive" '$2 == f {print $1}' "$checksums")
if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
  fail unsupported_platform "expirely v${version} publishes no ${archive}." "Use a runner with a platform the release lists in checksums.txt."
fi

cache_dir="${cache_root}/expirely/${version}/${arch}"
archive_path="${cache_dir}/${archive}"
source=cache
if [[ ! -f "$archive_path" || "$(sha256 "$archive_path")" != "$expected" ]]; then
  source=download
  archive_path="${work}/${archive}"
  status=$(download "${base_url}/${archive}" "$archive_path")
  case "$status" in
    200) ;;
    404) fail version_not_found "expirely v${version} has no ${archive}." "See https://github.com/${repo}/releases/tag/v${version}." ;;
    *) fail download_failed "Downloading ${archive} failed with HTTP ${status}." "Rerun the job; GitHub release downloads fail now and then." ;;
  esac
  actual=$(sha256 "$archive_path")
  if [[ "$actual" != "$expected" ]]; then
    fail checksum_mismatch "${archive} has SHA-256 ${actual}, but its checksum is ${expected}." "Do not use this archive; rerun the job, and report it at https://github.com/bycavii/expirely-action/issues if it happens again."
  fi
  if mkdir -p "$cache_dir" 2>/dev/null && cp "$archive_path" "${cache_dir}/${archive}.tmp" 2>/dev/null; then
    mv -f "${cache_dir}/${archive}.tmp" "${cache_dir}/${archive}" 2>/dev/null || true
  fi
fi

verify=false
case "$verify_mode" in
  true) verify=true ;;
  auto) [[ "$version" != "$default_version" && "${EXPIRELY_SERVER_URL:-https://github.com}" == https://github.com ]] && verify=true ;;
esac
provenance="checksum verified"
if [[ "$verify" == true ]]; then
  need gh "Install the GitHub CLI on the runner, or set verify-attestation: false to rely on the checksum alone."
  [[ -n "${GH_TOKEN:-}" ]] || fail token_missing "gh attestation verify needs a token, even for a public repository." "Keep the default token input, or set verify-attestation: false to rely on the checksum alone."
  if ! attestation=$(gh attestation verify "$archive_path" --repo "$repo" --signer-workflow "$signer" \
    --source-ref refs/heads/main --deny-self-hosted-runners 2>&1); then
    fail attestation_failed "${archive} has no valid build provenance from ${signer}: ${attestation}" "Do not use this archive; report it at https://github.com/bycavii/expirely-action/issues."
  fi
  provenance="checksum and build provenance verified"
fi

bin_dir="${work}/bin"
mkdir -p "$bin_dir"
if [[ "$ext" == tar.gz ]]; then
  tar -xzf "$archive_path" -C "$bin_dir" expirely
elif command -v unzip >/dev/null 2>&1; then
  unzip -q -o "$archive_path" expirely.exe -d "$bin_dir"
else
  EXPIRELY_ZIP=$(native_path "$archive_path") EXPIRELY_DEST=$(native_path "$bin_dir") \
    powershell -NoProfile -NonInteractive -Command "Expand-Archive -LiteralPath \$env:EXPIRELY_ZIP -DestinationPath \$env:EXPIRELY_DEST -Force"
fi
binary="${bin_dir}/${exe}"
[[ -f "$binary" ]] || fail download_failed "${archive} holds no ${exe}." "Report it at https://github.com/bycavii/expirely-action/issues."
chmod +x "$binary"

reported=$("$binary" --version 2>/dev/null || true)
if [[ "$reported" != *"v${version}"* ]]; then
  fail checksum_mismatch "The installed binary reports ${reported:-nothing} instead of v${version}." "Report it at https://github.com/bycavii/expirely-action/issues."
fi

printf '%s\n' "$(native_path "$bin_dir")" >>"$GITHUB_PATH"
set_output version "$version"
set_output path "$(native_path "$binary")"
echo "Installed expirely ${version} for ${os}/${arch} from ${source}, ${provenance}."

if [[ "$install_only" == true ]]; then
  exit 0
fi

command_args=("${extra_args[@]}" --json --status all)
[[ -n "$warn_days" ]] && command_args+=(--warn-days "$warn_days")
[[ -n "$targets_file" ]] && command_args+=(--file "$targets_file")
((${#targets[@]})) && command_args+=(-- "${targets[@]}")

stop_token=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
report="${work}/report.json"
stderr_log="${work}/stderr.txt"

echo "::stop-commands::${stop_token}"
printf 'Running: expirely'
printf ' %q' "${command_args[@]}"
printf '\n'
set +e
(cd -- "$working_directory" && exec "$binary" "${command_args[@]}") >"$report" 2>"$stderr_log"
exit_code=$?
set -e
if [[ -s "$stderr_log" ]]; then
  cat "$stderr_log"
fi
echo "::${stop_token}::"

set_output exit-code "$exit_code"
set_output report-file "$(native_path "$report")"

if ! jq -e '.summary' "$report" >/dev/null 2>&1; then
  error_code=$(jq -r '.error.code // empty' "$stderr_log" 2>/dev/null || true)
  error_message=$(jq -r '.error.message // empty' "$stderr_log" 2>/dev/null || true)
  error_fix=$(jq -r '.error.remediation // empty' "$stderr_log" 2>/dev/null || true)
  if [[ -z "$error_message" ]]; then
    error_message=$(head -c 2000 "$stderr_log")
  fi
  error_message=${error_message%.}
  fail expirely_failed "expirely exited ${exit_code}${error_code:+ with ${error_code}}: ${error_message}." "${error_fix:-See the log above.}"
fi

IFS=$'\t' read -r total ok expiring expired errors < <(jq -r '[.summary.total, .summary.ok, .summary.expiring, .summary.expired, .summary.error] | map(. // 0) | @tsv' "$report")
unreadable=$(jq -r '(.unreadable // []) | join(",")' "$report")
min_days_left=$(jq -r '[.results[].days_left | select(. != null)] | min // empty' "$report")
report_warn_days=$(jq -r '.warn_days' "$report")

set_output total "$total"
set_output ok "$ok"
set_output expiring "$expiring"
set_output expired "$expired"
set_output errors "$errors"
set_output unreadable "$unreadable"
set_output min-days-left "$min_days_left"

attention=$((expiring + expired + errors))
summary_file=""
if ((attention > 0)) || [[ -n "$unreadable" ]]; then
  summary_file="${work}/summary.md"
  {
    if ((attention == 1)); then
      echo "## expirely: 1 certificate needs attention"
    else
      echo "## expirely: ${attention} certificates need attention"
    fi
    echo
    if ((attention > 0)); then
      echo "| Status | Target | Expires | Days left | Details |"
      echo "| --- | --- | --- | --- | --- |"
      jq -r --argjson max "$max_rows" '
        def cell: tostring | gsub("[\r\n]+"; " ") | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;") | gsub("\\|"; "\\|");
        def detail:
          if .error then (.error.reason // .error.message // .error.code)
          elif .trust_issue and .trust_issue != "expired" then "not trusted: " + .trust_issue
          elif .acm then "ACM " + (.acm.region // "") + ", in use by " + ((.acm.in_use_by // []) | length | tostring)
          elif .gcp then "Google Cloud " + (.gcp.location // "") + ", in use by " + ((.gcp.in_use_by // []) | length | tostring)
          else "" end;
        [.results[] | select(.status != "ok")][:$max][]
        | "| \(.status) | `\(.target | cell | gsub("`"; ""))` | \((.expires_at // "") | .[0:10]) | \(.days_left // "") | \(detail | cell) |"
      ' "$report"
      if ((attention > max_rows)); then
        echo
        echo "$((attention - max_rows)) more are in the JSON report."
      fi
      echo
    fi
    if [[ -n "$unreadable" ]]; then
      echo "Could not read ${unreadable//,/, }; certificates kept there are missing from this report."
      echo
    fi
    echo "Checked ${total}: ${ok} ok, ${expiring} expiring, ${expired} expired, ${errors} unreadable. warn-days ${report_warn_days}, expirely ${version}."
  } >"$summary_file"
fi
set_output summary-file "$([[ -n "$summary_file" ]] && native_path "$summary_file")"

if [[ "$want_summary" == true && -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  if [[ -n "$summary_file" ]]; then
    cat "$summary_file" >>"$GITHUB_STEP_SUMMARY"
  elif ((total == 0)); then
    printf '## expirely: no certificates found\n\nexpirely %s read no certificate.\n' "$version" >>"$GITHUB_STEP_SUMMARY"
  else
    soonest=$(jq -r '[.results[] | select(.days_left != null)] | min_by(.days_left) | "\(.target) expires first, in \(.days_left) days (\(.expires_at[0:10]))"' "$report")
    if ((total == 1)); then
      heading="the certificate is ok"
    else
      heading="all ${total} certificates are ok"
    fi
    printf '## expirely: %s\n\n%s. warn-days %s, expirely %s.\n' "$heading" "$soonest" "$report_warn_days" "$version" >>"$GITHUB_STEP_SUMMARY"
  fi
fi

if [[ "$want_annotations" == true ]]; then
  shown_errors=0
  shown_warnings=0
  hidden=0
  while IFS=$'\x1f' read -r status target days expires reason; do
    case "$status" in
      expired)
        kind=error
        title="Certificate expired: ${target}"
        message="${target} expired $((-days)) days ago, on ${expires}."
        ;;
      expiring)
        kind=warning
        title="Certificate expiring: ${target}"
        message="${target} expires in ${days} days, on ${expires}."
        ;;
      *)
        kind=error
        title="Certificate not read: ${target}"
        message="${target} could not be read: ${reason}."
        ;;
    esac
    if [[ "$kind" == error ]]; then
      if ((shown_errors >= max_annotations)); then
        hidden=$((hidden + 1))
        continue
      fi
      shown_errors=$((shown_errors + 1))
    else
      if ((shown_warnings >= max_annotations)); then
        hidden=$((hidden + 1))
        continue
      fi
      shown_warnings=$((shown_warnings + 1))
    fi
    echo "::${kind} title=$(escape_property "$title")::$(escape_data "$message")"
  done < <(jq -r '.results[] | select(.status != "ok") | [.status, .target, (.days_left // 0), ((.expires_at // "")[0:10]), (.error.reason // .error.message // "")] | map(tostring | gsub("[\u001f\r\n]"; " ")) | join("\u001f")' "$report")
  if [[ -n "$unreadable" ]]; then
    echo "::error title=$(escape_property "Not read: ${unreadable}")::$(escape_data "Could not read ${unreadable//,/, }; certificates kept there are missing from this report.")"
  fi
  if ((hidden > 0)); then
    echo "::notice title=expirely::$(escape_data "${hidden} more certificates need attention; GitHub shows ${max_annotations} annotations of each kind, and the job summary lists them all.")"
  fi
fi

echo "expirely: ${total} checked, ${ok} ok, ${expiring} expiring, ${expired} expired, ${errors} unreadable${unreadable:+, could not read ${unreadable}}."

reasons=()
if ((expired > 0)) && [[ "$fail_on" != never ]]; then
  reasons+=("${expired} expired (fail-on: ${fail_on})")
fi
if ((expiring > 0)) && [[ "$fail_on" == expiring ]]; then
  reasons+=("${expiring} expiring (fail-on: expiring)")
fi
if [[ "$fail_on_error" == true ]] && { ((errors > 0)) || [[ -n "$unreadable" ]]; }; then
  reasons+=("${errors} unreadable${unreadable:+ plus ${unreadable}} (fail-on-error: true)")
fi
if ((${#reasons[@]} > 0)); then
  joined=$(printf '%s; ' "${reasons[@]}")
  echo "Failing the step: ${joined%; }. Set fail-on: never and fail-on-error: false to report without failing."
  exit 1
fi
