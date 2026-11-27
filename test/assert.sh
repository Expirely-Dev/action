#!/usr/bin/env bash
set -uo pipefail

failures=0

expect() {
  local name=$1 got=$2 want=$3
  if [[ "$got" == "$want" ]]; then
    echo "ok   ${name} = ${got}"
  else
    echo "FAIL ${name} = \"${got}\", want \"${want}\""
    failures=$((failures + 1))
  fi
}

expect_file() {
  local name=$1 path=$2
  if [[ -n "$path" && -f "$path" ]]; then
    echo "ok   ${name} exists"
  else
    echo "FAIL ${name} = \"${path}\", want an existing file"
    failures=$((failures + 1))
  fi
}

expect "valid: outcome" "${OK_OUTCOME:-}" success
expect "valid: exit-code" "${OK_EXIT_CODE:-}" 0
expect "valid: total" "${OK_TOTAL:-}" 1
expect "valid: ok" "${OK_OK:-}" 1
expect "valid: min-days-left" "${OK_MIN_DAYS_LEFT:-}" 199
expect "valid: summary-file" "${OK_SUMMARY_FILE:-}" ""
expect_file "valid: report-file" "${OK_REPORT_FILE:-}"

expect "expiring: outcome" "${EXPIRING_OUTCOME:-}" failure
expect "expiring: exit-code" "${EXPIRING_EXIT_CODE:-}" 1
expect "expiring: expiring" "${EXPIRING_EXPIRING:-}" 1

expect "fail-on expired: outcome" "${ALLOWED_OUTCOME:-}" success

expect "report only: outcome" "${REPORT_OUTCOME:-}" success
expect "report only: expired" "${REPORT_EXPIRED:-}" 1
expect "report only: errors" "${REPORT_ERRORS:-}" 1
expect_file "report only: summary-file" "${REPORT_SUMMARY_FILE:-}"

expect "unreadable: outcome" "${UNREADABLE_OUTCOME:-}" failure
expect "unreadable: exit-code" "${UNREADABLE_EXIT_CODE:-}" 3

expect "verify-attestation: outcome" "${ATTESTATION_OUTCOME:-}" success

expect "invalid input: outcome" "${BAD_INPUT_OUTCOME:-}" failure
expect "invalid input: nothing installed" "${BAD_INPUT_VERSION:-}" ""

expect_file "install-only: path" "${INSTALLED_PATH:-}"
on_path=$(expirely --version 2>&1)
expect "install-only: expirely on PATH" "$on_path" "{\"version\":\"v${INSTALLED_VERSION:-}\"}"

if ((failures > 0)); then
  echo "${failures} checks failed"
  exit 1
fi
echo "every check passed"
