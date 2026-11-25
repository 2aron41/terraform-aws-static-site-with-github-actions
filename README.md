# Terraform AWS Static Site With GitHub Actions

Pull requests check Terraform formatting and validity. A manual GitHub Actions workflow publishes the demo page to S3 and invalidates CloudFront.

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
├── Makefile                    # Terraform shortcuts
├── .github/workflows/          # Pull request checks and manual site deployment
├── site/index.html             # Demo page served by CloudFront
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

If the AWS account already has the GitHub OIDC provider, use that provider. Otherwise, create it with the AWS CLI. [AWS IAM OIDC provider documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

### 2. Bootstrap remote state

Create the S3 bucket and DynamoDB table for Terraform state before the first `init`:

```bash
aws s3api create-bucket --bucket my-tfstate-bucket --region us-east-1
aws s3api put-bucket-versioning \
  --bucket my-tfstate-bucket \
  --region us-east-1 \
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

### 4. Provision the site infrastructure

For a new deployment, edit `environments/dev.tfvars`. Set `project_name` so the resulting S3 bucket name is globally unique. Set `domain_name` and `hosted_zone_id` to your domain and its public Route 53 hosted zone. Set `github_org` and `github_repo` to the owner and name of the repository that will run the workflow. Use the same account as the OIDC provider. If the site infrastructure is already provisioned, initialize the existing backend and select its workspace to read the outputs.

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

## Verify pull request checks

Every pull request runs **Terraform format and validate**. To run the same commands locally, use Terraform 1.9.8 from `.terraform-version` and a fresh checkout so the local working directory starts without remote backend metadata.

```bash
terraform fmt -check -recursive
terraform init -backend=false -input=false
make validate
```

Initialization downloads the AWS provider. It skips the remote backend, and all three commands can run without AWS credentials.

## Configure and run the demo deployment

1. From the initialized Terraform checkout, select the workspace for the site you want to publish to. Read all the deployment outputs from that workspace.

   ```bash
   terraform workspace select dev
   terraform output -raw deploy_role_arn
   terraform output -raw s3_bucket_name
   terraform output -raw cloudfront_distribution_id
   terraform output -raw cloudfront_domain_name
   ```

2. In the GitHub repository, open **Settings → Secrets and variables → Actions**. Add these repository settings using values from the same workspace.

   | Kind | Name | Value |
   | --- | --- | --- |
   | Secret | `DEPLOY_ROLE_ARN` | `terraform output -raw deploy_role_arn` |
   | Variable | `SITE_BUCKET` | `terraform output -raw s3_bucket_name` |
   | Variable | `CLOUDFRONT_DISTRIBUTION_ID` | `terraform output -raw cloudfront_distribution_id` |
   | Variable | `AWS_REGION` | The site bucket's region, set by `aws_region` in the workspace's tfvars file |

3. Once the workflow is on `main`, open **Actions → Deploy demo site → Run workflow**, select `main`, and click **Run workflow**. The workflow uses temporary credentials from the deploy role, writes `site/index.html` to the bucket's `index.html` key, and waits for invalidation of `/` and `/index.html`. This replaces the current homepage in the configured bucket.
4. Check that **Upload demo page** and **Invalidate CloudFront and wait** both succeeded. From a checkout of the deployed revision, verify the CloudFront root and explicit page URL return the committed file. Run this from the initialized Terraform checkout for the same workspace.

   ```bash
   CLOUDFRONT_URL="https://$(terraform output -raw cloudfront_domain_name)"
   curl --fail --silent --show-error "$CLOUDFRONT_URL/" | diff -u site/index.html -
   curl --fail --silent --show-error "$CLOUDFRONT_URL/index.html" | diff -u site/index.html -
   ```

   Both comparisons should exit successfully with no diff. Once DNS resolves, repeat the root request using the custom domain from your tfvars file.

## Teardown

```bash
make destroy ENV=dev
```

The root module uses the static-site module's default `s3_force_destroy = false`. Empty the bucket, including object versions and delete markers, before destroying the site.
