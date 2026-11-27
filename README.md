# expirely action

Fail CI before a TLS certificate expires.

```yaml
- uses: expirely-dev/action@v3
  with:
    targets: |
      example.com
      api.example.com:8443
```

The action installs [expirely](https://github.com/expirely-dev/expirely-cli), checks the archive against its SHA-256, and runs it. The step fails when a certificate expires within 30 days or a target cannot be read, and expirely writes a job summary and an annotation for each certificate that needs attention. It runs on Linux, macOS and Windows, on X64 and ARM64.

## Inputs

| Input | Description |
| --- | --- |
| `targets` | Endpoints to check, one per line, as `host`, `host:port` or `https://` URL. Blank lines and lines starting with `#` are skipped. |
| `args` | Extra arguments of `expirely tls`, one per line, placed before the targets; start with `aws` or `gcp` to read a cloud account. See [expirely tls](https://github.com/expirely-dev/expirely-cli/blob/main/docs/cli/commands/tls.mdx). |
| `version` | expirely version to install. The default is pinned in [`action.yml`](action.yml), and its checksums ship in [`versions/`](versions). |

With neither `targets` nor `args`, the action only installs expirely and adds it to `PATH`.

## Examples

Warn 21 days ahead, with the targets in a file:

```yaml
- uses: actions/checkout@v7
  with:
    persist-credentials: false
- uses: expirely-dev/action@v3
  with:
    args: |
      --warn-days
      21
      --file
      certificates.txt
```

Every region of an AWS account, with credentials from OIDC; the role needs `acm:ListCertificates`, `acm:DescribeCertificate` and `ec2:DescribeRegions`:

```yaml
- uses: aws-actions/configure-aws-credentials@v6
  with:
    role-to-assume: arn:aws:iam::123456789012:role/expirely
    aws-region: us-east-1
- uses: expirely-dev/action@v3
  with:
    args: |
      aws
      --region
      all
```

Report without failing the job:

```yaml
- uses: expirely-dev/action@v3
  continue-on-error: true
  with:
    targets: example.com
```

Run expirely yourself:

```yaml
- uses: expirely-dev/action@v3
- run: expirely tls --json example.com | jq '.summary'
```

## Exit codes

The step ends with expirely's exit code: `0` when every certificate is ok, `1` when one is expired, revoked or expiring, `2` for a usage error, `3` when a target could not be read or a certificate's end date is unknown. The action itself fails before running expirely when the runner has no expirely release, the download fails, or the archive does not match its checksum.

## Versions

`v3` points at the latest `v3.x.y` release. A new expirely version that breaks its exit codes or JSON comes with a new major version of the action. To pin the action and, with it, the exact expirely binary, use a full commit SHA with the version in a comment, which Dependabot and Renovate keep current:

```yaml
- uses: expirely-dev/action@<full-commit-sha> # v3.0.0
```

`v3` installs expirely 0.10.0, which changed what `v2` users may parse: the JSON report is `schema_version` 2, with `trusted`, `trust_issue`, `verify_error`, `leaf` and `chain` under `tls`; a cloud certificate without an end date is `unknown` and exits `3`; and `expirely TARGET`, `expirely aws` and `expirely gcp` are now `expirely tls TARGET`, `expirely tls aws` and `expirely tls gcp`. The `targets` and `args` inputs work as before. `v2` stays on expirely 0.9.

The pinned version's checksums ship with the action; a workflow here checks the build provenance of every archive of a new expirely release before it makes that release the default. Any other `version` is checked against the `checksums.txt` of its release.

## License

[Apache-2.0](LICENSE)
