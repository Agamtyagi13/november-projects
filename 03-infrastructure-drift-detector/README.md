# Infrastructure Drift Detector

Provisions a small AWS environment (S3 bucket + versioning + SQS queue) with **Terraform**, then runs a **scheduled Python check** that detects configuration drift and **reports differences without changing anything**.

## How it avoids silent changes
The detector only runs `terraform plan` and `terraform show -json`. It **never runs `apply`**, takes no state lock (`-lock=false`), and exits with a code instead of fixing anything. Remediation is a human decision.

| Finding | Meaning | Source in plan JSON |
|---|---|---|
| `drift` | Someone changed real infrastructure outside Terraform | `resource_drift` |
| `config-diff` | Real infrastructure no longer matches the code | `resource_changes` |

Exit codes: `0` no drift · `2` drift detected · `1` error. Reports: `reports/drift-report.md` and `.json`. Sensitive values are masked. Noisy attributes can be skipped with `--ignore 'tags_all.*'`.

## Run it locally (LocalStack, no AWS account)
```bash
make up                 # LocalStack on :4566
make apply              # create the baseline environment
make drift              # -> "NO DRIFT" (exit 0)
make simulate           # change tags, versioning and queue timeout out-of-band
make drift              # -> DRIFT DETECTED (exit 2) with attribute-level diff
make test               # unit tests (no terraform/AWS needed)
make down
```
Needs: Docker, Terraform ≥ 1.5, Python 3.9+, `aws` CLI (only for `simulate`).

## Scheduled check (GitHub Actions)
`.github/workflows/drift-check.yml` runs every 6 hours and on demand: unit tests → baseline → detect → upload report → **opens a GitHub issue** if drift is found → optional webhook (`DRIFT_WEBHOOK_URL` secret). Run it manually with `simulate_drift = true` to watch it catch drift end-to-end.

## Use against real AWS
Set `-var use_localstack=false`, configure a remote state backend (S3 + DynamoDB lock) and AWS credentials via GitHub OIDC (no static keys), and drop the LocalStack service/provision steps from the workflow.
