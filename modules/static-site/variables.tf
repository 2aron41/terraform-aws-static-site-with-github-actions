variable "project_name" {
  description = "Short identifier used in resource names."
  type        = string
}

variable "environment" {
  description = "Deployment environment — dev or prod."
  type        = string
}

variable "domain_name" {
  description = "Apex domain or subdomain served by this CloudFront distribution."
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID for the domain."
  type        = string
}

variable "github_org" {
  description = "GitHub organization or username that owns the Actions-enabled repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name. The OIDC trust policy is scoped to this repo."
  type        = string
}

variable "s3_force_destroy" {
  description = "Allow terraform destroy to delete the S3 bucket even when it contains objects. Set true for dev, false for prod."
  type        = bool
  default     = false
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 covers US/EU and is cheapest."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

variable "default_root_object" {
  description = "Object CloudFront returns for requests to the root URL."
  type        = string
  default     = "index.html"
}
