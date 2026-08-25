SHELL := /bin/bash

# --- Terraform --------------------------------------------------------------
TF_ARGS ?=

.PHONY: init plan apply destroy output validate

init:
	cd terraform && terraform init

plan: init
	cd terraform && terraform plan $(TF_ARGS)

apply: init
	cd terraform && terraform apply $(TF_ARGS)

output: init
	cd terraform && terraform output -raw registration_token

validate:
	cd terraform && terraform validate

destroy:
	cd terraform && terraform destroy $(TF_ARGS)

# --- Ansible ----------------------------------------------------------------
ANSIBLE_EXTRA ?=

provision:
	cd ansible && ansible-playbook playbooks/provision.yml $(ANSIBLE_EXTRA)

# --- Flash ------------------------------------------------------------------
FLASH_ARGS ?=
flash:
	scripts/flash.sh $(FLASH_ARGS)

# --- gh helpers -------------------------------------------------------------
HEALTH_ARGS ?=
health:
	scripts/healthcheck.sh $(HEALTH_ARGS)

REGISTER_ARGS ?=
register:
	scripts/register.sh $(REGISTER_ARGS)
