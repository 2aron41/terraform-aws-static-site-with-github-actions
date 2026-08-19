variable "project_name" {
  description = "Short identifier used for naming all resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment — dev or prod."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be one of: dev, prod."
  }
}

variable "aws_region" {
  description = "Primary AWS region for S3, DynamoDB state lock, and supporting resources."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Apex domain served by the CloudFront distribution (e.g., example.com)."
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for the domain."
  type        = string
}

variable "github_org" {
  description = "GitHub organization or username that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org prefix)."
  type        = string
}
