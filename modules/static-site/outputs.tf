output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = aws_cloudfront_distribution.site.id
}

output "s3_bucket_name" {
  description = "Name of the S3 origin bucket."
  value       = aws_s3_bucket.site.bucket
}

output "deploy_role_arn" {
  description = "ARN of the least-privilege IAM role GitHub Actions assumes via OIDC."
  value       = aws_iam_role.deploy.arn
}
