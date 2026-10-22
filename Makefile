ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
TOOLS_DIR := $(ROOT_DIR)/.tools
TOFU := $(TOOLS_DIR)/tofu
VENV := $(ROOT_DIR)/.venv
PY := $(VENV)/bin/python

export PATH := $(TOOLS_DIR):$(PATH)
export KUBECONFIG := $(ROOT_DIR)/infra/.kube/config
export TF_VAR_tools_dir := $(TOOLS_DIR)
export TF_IN_AUTOMATION := 1
export TF_INPUT := 0

TOFU_ARGS :=
ifeq ($(OBSERVABILITY),0)
TOFU_ARGS += -var=enable_observability=false
endif

.PHONY: help preflight tools up down smoke load test lint lint-python lint-terraform lint-manifests build

help:
	@printf '%s\n' \
		'up       Create the kind cluster, deploy the platform, and run the smoke test.' \
		'down     Destroy the kind cluster.' \
		'smoke    Check health, auth, predictions, metrics, and Grafana.' \
		'load     Send load and wait for the autoscaler to add pods.' \
		'test     Run the Python unit tests.' \
		'lint     Run the Python, OpenTofu, Helm, and manifest checks.' \
		'build    Build the inference image locally.' \
		'tools    Download OpenTofu, kind, kubectl, Helm, TFLint, and kubeconform into .tools.'

preflight:
	@docker info >/dev/null 2>&1 || { echo 'Docker is not running. Start Docker and run make up again.'; exit 1; }

tools:
	@bash $(ROOT_DIR)/scripts/bootstrap-tools.sh

up: preflight tools
	@mkdir -p $(ROOT_DIR)/infra/.kube
	$(TOFU) -chdir=$(ROOT_DIR)/infra init -input=false
	$(TOFU) -chdir=$(ROOT_DIR)/infra apply -auto-approve $(TOFU_ARGS)
	$(MAKE) smoke

down: tools
	@mkdir -p $(ROOT_DIR)/infra/.kube
	$(TOFU) -chdir=$(ROOT_DIR)/infra init -input=false
	$(TOFU) -chdir=$(ROOT_DIR)/infra destroy -auto-approve $(TOFU_ARGS)

smoke: tools
	@bash $(ROOT_DIR)/scripts/smoke.sh

load: tools
	@API_URL="$$($(TOFU) -chdir=$(ROOT_DIR)/infra output -raw inference_url)" \
		API_KEY="$$($(TOFU) -chdir=$(ROOT_DIR)/infra output -raw api_key)" \
		NAMESPACE="$$($(TOFU) -chdir=$(ROOT_DIR)/infra output -raw namespace)" \
		python3 $(ROOT_DIR)/scripts/load_test.py

$(PY):
	python3 -m venv $(VENV)
	$(PY) -m pip install --upgrade pip
	$(PY) -m pip install -r $(ROOT_DIR)/app/requirements-dev.txt

test: $(PY)
	$(PY) -m pytest $(ROOT_DIR)/app/tests

lint-python: $(PY)
	$(PY) -m ruff check $(ROOT_DIR)/app
	$(PY) -m ruff format --check $(ROOT_DIR)/app

lint-terraform: tools
	$(TOFU) fmt -check -recursive $(ROOT_DIR)/infra
	$(TOFU) -chdir=$(ROOT_DIR)/infra init -backend=false -input=false
	$(TOFU) -chdir=$(ROOT_DIR)/infra validate
	tflint --chdir=$(ROOT_DIR)/infra --init
	tflint --chdir=$(ROOT_DIR)/infra

lint-manifests: tools
	@bash $(ROOT_DIR)/scripts/lint-manifests.sh

lint: lint-python lint-terraform lint-manifests

build: preflight
	docker build --tag k8s-ml-inference:local $(ROOT_DIR)/app
