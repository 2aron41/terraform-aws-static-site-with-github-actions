.PHONY: init plan apply destroy fmt validate

ENV ?= dev
BACKEND_CONFIG ?= backend.hcl
VAR_FILE       ?= environments/$(ENV).tfvars

init:
	terraform init -backend-config=$(BACKEND_CONFIG)

fmt:
	terraform fmt -recursive

validate:
	terraform validate

plan:
	terraform plan -var-file=$(VAR_FILE) -out=tfplan

apply:
	terraform apply tfplan

destroy:
	terraform destroy -var-file=$(VAR_FILE)

# Switch workspace to match the environment (workspaces mirror ENV).
workspace:
	terraform workspace select $(ENV) || terraform workspace new $(ENV)
