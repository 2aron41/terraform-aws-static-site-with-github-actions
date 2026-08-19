module "static_site" {
  source = "./modules/static-site"

  project_name   = var.project_name
  environment    = var.environment
  domain_name    = var.domain_name
  hosted_zone_id = var.hosted_zone_id
  github_org     = var.github_org
  github_repo    = var.github_repo

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}
