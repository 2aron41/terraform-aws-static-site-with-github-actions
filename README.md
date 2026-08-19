# Terraform AWS Static Site With GitHub Actions

> Status: foundation — Terraform module wired, GitHub Actions CI/CD not yet added.

Terraform module that provisions a production-grade static site on AWS:
S3 origin behind a CloudFront distribution with a custom ACM-issued TLS certificate,
Route 53 DNS records, and a least-privilege IAM deploy role that GitHub Actions
assumes via OIDC — no long-lived access keys stored anywhere.

## Architecture

```
GitHub Actions (OIDC)
        │
        ▼ sts:AssumeRoleWithWebIdentity
  IAM Deploy Role
        │
        ├─ s3:PutObject / s3:DeleteObject / s3:ListBucket → S3 Bucket (private)
        │                                                        │
        │                                              Origin Access Control
        │                                                        │
        └─ cloudfront:CreateInvalidation         ────► CloudFront Distribution
                                                              │
                                              ACM Certificate (us-east-1)
                                                              │
                                                   Route 53 A records
                                                  (apex + www aliases)
```

No objects in S3 are ever public. CloudFront fetches via OAC (sigv4), so the bucket
policy allows only the distribution's service principal.

## Layout

```
.
├── main.tf                     # Root module — wires everything together
├── variables.tf                # Root variables
├── outputs.tf                  # Root outputs (CloudFront URL, bucket name, role ARN)
├── versions.tf                 # Provider requirements and backend block
├── backend.hcl.example         # Template for -backend-config at init
├── Makefile                    # Shortcuts: init, plan, apply, destroy
├── environments/
│   ├── dev.tfvars
│   └── prod.tfvars
└── modules/
    └── static-site/
        ├── main.tf             # S3, OAC, ACM, CloudFront, Route 53, OIDC role
        ├── variables.tf
        ├── outputs.tf
        └── versions.tf
```

## Prerequisites

- Terraform >= 1.9 (`tfenv` or `asdf` recommended — `.terraform-version` is present)
- AWS CLI configured, or an IAM role assumed in the shell
- A Route 53 hosted zone for your domain
- The GitHub OIDC provider created once per AWS account (see below)

## Initial Setup

### 1. Create the OIDC provider (one-time per account)

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

### 2. Bootstrap remote state

Create the S3 bucket and DynamoDB table for Terraform state before the first `init`:

```bash
aws s3api create-bucket --bucket my-tfstate-bucket --region us-east-1
aws s3api put-bucket-versioning \
  --bucket my-tfstate-bucket \
  --versioning-configuration Status=Enabled
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 3. Configure the backend

```bash
cp backend.hcl.example backend.hcl
# Edit backend.hcl — fill in your bucket name, key, and region
```

### 4. Deploy

```bash
make init ENV=dev
make workspace ENV=dev
make plan ENV=dev
make apply
```

## Environments

Two tfvars files drive the workspace separation:

| File                      | Workspace | Domain             |
|---------------------------|-----------|--------------------|
| environments/dev.tfvars   | dev       | dev.example.com    |
| environments/prod.tfvars  | prod      | example.com        |

Terraform workspaces keep the state files separate in the same S3 bucket.

## OIDC Trust Policy

The deploy role's trust policy is scoped to one repository:

```json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:<org>/<repo>:*"
    }
  }
}
```

The `sub` wildcard allows any ref (branch, tag, PR) in that repository.
To lock it further to `refs/heads/main` only, replace `*` with `ref:refs/heads/main`.

Only one secret lives in GitHub: `DEPLOY_ROLE_ARN` — the ARN output from `terraform apply`.
No AWS access key ID, no secret access key.

## Forking and Deploying

1. Fork this repository.
2. Follow the setup steps above with your own domain and AWS account.
3. Add `DEPLOY_ROLE_ARN` as a repository secret in GitHub settings.
4. Push a commit — the GitHub Actions workflow (added in a later commit) runs plan on
   PRs and apply on merge to main.

## Teardown

```bash
make destroy ENV=dev
```

`s3_force_destroy = true` in `dev.tfvars` allows destroy to empty the bucket.
In prod, set `s3_force_destroy = false` (the default) so the bucket refuses
destroy unless empty, preventing accidental data loss.
