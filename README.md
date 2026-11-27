# expirely-action

Fail CI before a TLS certificate expires.

This action installs [expirely](https://github.com/bycavii/expirely-cli), checks that the binary is the one the expirely release workflow built, and reads the certificates of your endpoints, of AWS Certificate Manager or of a Google Cloud project. It fails the step when a certificate expires within 30 days, writes a job summary, and annotates every certificate that needs attention.

```yaml
- uses: bycavii/expirely-action@v1
  with:
    targets: |
      example.com
      api.example.com:8443
```

It runs on Linux, macOS and Windows, on X64 and ARM64, and needs no token, secret or setup step.

## Quick start

Check your certificates on every pull request and every weekday morning:

```yaml
name: certificates

on:
  pull_request:
  schedule:
    - cron: '0 8 * * 1-5'

permissions: {}

jobs:
  expirely:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: bycavii/expirely-action@v1
        with:
          targets: |
            example.com
            api.example.com:8443
```

A certificate that expires within 30 days fails the job, and the job summary lists it:

```text
## expirely: 1 certificate needs attention

| Status   | Target              | Expires    | Days left | Details |
| -------- | ------------------- | ---------- | --------- | ------- |
| expiring | `api.example.com:8443` | 2026-12-07 | 9        |         |

Checked 2: 1 ok, 1 expiring, 0 expired, 0 unreadable. warn-days 30, expirely 0.6.0.
```

## Examples

### Keep the targets in a file

```yaml
- uses: actions/checkout@v7
  with:
    persist-credentials: false
- uses: bycavii/expirely-action@v1
  with:
    targets-file: certificates.txt
    warn-days: 21
```

`certificates.txt` holds one target per line, as `host`, `host:port`, `[ipv6]:port` or `https://host/path`; the port defaults to 443.

### Open an issue instead of failing a schedule

```yaml
name: certificates

on:
  schedule:
    - cron: '0 8 * * 1-5'

permissions: {}

jobs:
  expirely:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
    steps:
      - id: expirely
        uses: bycavii/expirely-action@v1
        with:
          targets: |
            example.com
            api.example.com:8443
          fail-on: never
      - if: steps.expirely.outputs.summary-file != ''
        uses: peter-evans/create-issue-from-file@v6
        with:
          title: Certificates need attention
          content-filepath: ${{ steps.expirely.outputs.summary-file }}
          labels: certificates
```

`summary-file` is empty when every certificate is ok, so an issue is only opened when something needs attention. Each such run opens a new issue; to keep updating one, create it once and pass its number as `issue-number`.

### Every region of an AWS account

```yaml
permissions:
  contents: read
  id-token: write
steps:
  - uses: aws-actions/configure-aws-credentials@v6
    with:
      role-to-assume: arn:aws:iam::123456789012:role/expirely
      aws-region: us-east-1
  - uses: bycavii/expirely-action@v1
    with:
      args: |
        aws
        --region
        all
```

The role needs `acm:ListCertificates`, `acm:DescribeCertificate` and `ec2:DescribeRegions`, which the AWS managed policy `ReadOnlyAccess` grants. A region the role cannot read, such as one a service control policy denies, is listed in the `unreadable` output and fails the step unless `fail-on-error: false`. See [expirely aws](https://github.com/bycavii/expirely-cli/blob/main/docs/cli/aws.mdx).

### A Google Cloud project

```yaml
permissions:
  contents: read
  id-token: write
steps:
  - uses: google-github-actions/auth@v3
    with:
      workload_identity_provider: projects/123456789/locations/global/workloadIdentityPools/github/providers/github
      service_account: expirely@acme-production.iam.gserviceaccount.com
  - uses: bycavii/expirely-action@v1
    with:
      args: |
        gcp
        --project
        acme-production
```

### Use expirely in your own steps

```yaml
- uses: bycavii/expirely-action@v1
  with:
    install-only: true
- run: expirely --json --warn-days 14 example.com | jq '.summary'
```

## Inputs

Every input is optional. Booleans take `true` or `false`.

| Input | Default | Description |
| --- | --- | --- |
| `targets` | | Endpoints to check, one per line, as `host`, `host:port` or `https://` URL. Blank lines and lines starting with `#` are skipped. |
| `targets-file` | | Path to a file with one target per line. Combined with `targets`. |
| `warn-days` | `30` | A certificate that expires within this many days counts as `expiring`. |
| `fail-on` | `expiring` | Which findings fail the step: `expiring` (expiring or expired), `expired` (expired only) or `never`. |
| `fail-on-error` | `true` | Fail the step when a target, or a cloud region, could not be read. |
| `summary` | `true` | Write the job summary. |
| `annotations` | `true` | Annotate each certificate that needs attention, most urgent first. GitHub shows 10 annotations of each kind per step; the summary lists them all. |
| `args` | | Extra expirely arguments, one per line, placed before the others. Start with `aws` or `gcp` to read a cloud account. See [expirely --help](https://github.com/bycavii/expirely-cli/blob/main/docs/cli/expirely.mdx). |
| `working-directory` | `.` | Directory expirely runs in, for relative paths in `targets-file` and `args`. |
| `install-only` | `false` | Install expirely and add it to `PATH` without running a check. |
| `version` | pinned | expirely version, as `0.6.0`, `v0.6.0` or `latest`. The default is pinned in [`action.yml`](action.yml), and its checksums ship with the action. |
| `verify-attestation` | `auto` | Check the archive's build provenance with `gh attestation verify`. `auto` checks every version other than the pinned one on github.com. |
| `token` | `github.token` | Token for `gh attestation verify` and for resolving `latest`. It is only sent to github.com. |

At least one of `targets`, `targets-file` or `args` is needed, unless `install-only` is `true`.

## Outputs

| Output | Description |
| --- | --- |
| `version` | The expirely version installed, such as `0.6.0`. |
| `path` | Absolute path of the expirely binary. |
| `exit-code` | The expirely exit code: `0` all ok, `1` expiring or expired, `2` usage error, `3` something could not be read. |
| `total` | Certificates checked. |
| `ok`, `expiring`, `expired` | Certificates in each status. |
| `errors` | Targets that could not be read. |
| `unreadable` | Cloud regions or locations that could not be read, comma-separated, such as `acm:ap-south-1`. |
| `min-days-left` | Days left on the certificate that expires first; negative once expired, empty when none was read. |
| `report-file` | Path to the full JSON report. Its fields are documented in [Output](https://github.com/bycavii/expirely-cli/blob/main/docs/reference/output.mdx). |
| `summary-file` | Path to the Markdown summary of what needs attention; empty when every certificate is ok. |

The outputs are set even when the step fails, so a later step with `if: always()` can read them.

## When the step fails

| Result | Fails the step |
| --- | --- |
| An `expired` certificate | Unless `fail-on: never` |
| An `expiring` certificate | Only with `fail-on: expiring`, the default |
| A target or region that could not be read | Unless `fail-on-error: false` |
| An invalid input, or an expirely usage error | Always |
| The archive does not match its checksum or its provenance | Always |

When the action itself cannot go on, it fails with one error annotation titled `expirely-action: <code>`, which says what happened and how to fix it:

| Code | Meaning |
| --- | --- |
| `invalid_input` | An input has a value it does not accept, or `version` is older than 0.6.0. |
| `no_targets` | None of `targets`, `targets-file` or `args` was set. |
| `unsupported_platform` | The runner is not Linux, macOS or Windows on X64 or ARM64. |
| `missing_tool` | `curl`, `jq` or, for provenance checks, `gh` is not installed. GitHub-hosted runners have all three. |
| `version_not_found` | The expirely release, or its archive for this runner, does not exist. |
| `download_failed` | GitHub did not serve the archive; rerun the job. |
| `checksum_mismatch` | The archive does not match its SHA-256. It is never run. |
| `token_missing` | Provenance was to be checked, and `token` is empty. |
| `attestation_failed` | The archive has no valid build provenance from the expirely release workflow. It is never run. |
| `expirely_failed` | expirely stopped before reporting, such as on an unknown flag in `args` or missing cloud credentials; the message carries expirely's own error code and remediation. |

## How the binary is verified

The action never runs an archive it has not checked:

1. The pinned version's `checksums.txt` ships with the action, in [`versions/`](versions). When a new expirely version becomes the default, a workflow here verifies the build provenance of every archive before it commits the checksums, so pinning this action to a commit pins the exact expirely binary it runs.
2. Any other version, including `latest`, is checked against the `checksums.txt` of its release and with `gh attestation verify`, which proves the archive was built by [the expirely release workflow](https://github.com/bycavii/expirely-cli/blob/main/.github/workflows/release.yml) on `main` of bycavii/expirely-cli, on a GitHub-hosted runner.
3. A verified archive is kept in the runner's tool cache and checked against its SHA-256 again before every later use.

Set `verify-attestation: true` to check the provenance of the pinned version as well; it adds about 6 seconds.

## Versions and pinning

`v1` always points at the latest `v1.x.y` release, and each release is immutable. Breaking changes, including a new expirely version that changes its exit codes or JSON, come with a new major version.

For a supply chain you control, pin the action to a full commit SHA with the version in a comment, which Dependabot and Renovate keep current:

```yaml
- uses: bycavii/expirely-action@<full-commit-sha> # v1.0.0
```

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

## Self-hosted runners and GitHub Enterprise Server

The runner needs `bash`, `curl` and `jq`, and `gh` for provenance checks, and must reach `github.com` to download expirely. On GitHub Enterprise Server, `token` is empty by default, because a token of your server means nothing to github.com: the pinned version runs on its vendored checksums, and any other version is checked against its `checksums.txt` alone unless you pass a github.com token and `verify-attestation: true`.

## Troubleshooting

- **`no_targets`**: set `targets`, `targets-file`, or `args` such as `aws`.
- **A target reads as `error` in CI but not on your machine**: the runner cannot reach it. Hosts on a private network need a self-hosted runner inside that network.
- **Only 10 annotations show**: GitHub shows 10 annotations of each kind per step. The job summary and `report-file` list every certificate.
- **`expirely_failed` with `aws_access_denied` or `gcp_access_denied`**: the credentials lack the read permissions listed in the examples above.

## License

[Apache-2.0](LICENSE)
