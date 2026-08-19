output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name. Map this to your apex/www DNS records."
  value       = module.static_site.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID, used to trigger cache invalidations in CI."
  value       = module.static_site.cloudfront_distribution_id
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket serving the site origin."
  value       = module.static_site.s3_bucket_name
}

output "deploy_role_arn" {
  description = "ARN of the IAM role GitHub Actions assumes via OIDC."
  value       = module.static_site.deploy_role_arn
}
