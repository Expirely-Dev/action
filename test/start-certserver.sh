#!/usr/bin/env bash
set -euo pipefail

exe=certserver
if [[ "${RUNNER_OS:-}" == Windows ]]; then
  exe=certserver.exe
fi
temp=${RUNNER_TEMP:?}
(cd "$(dirname "$0")/certserver" && go build -o "${temp}/${exe}" .)
"${temp}/${exe}" -ca "${temp}/ca.pem" >"${temp}/certserver.log" 2>&1 &

for _ in $(seq 1 150); do
  if [[ -f "${temp}/ca.pem" ]]; then
    cat "${temp}/certserver.log"
    exit 0
  fi
  sleep 0.2
done
echo "the test TLS server did not start within 30s:" >&2
cat "${temp}/certserver.log" >&2
exit 1
