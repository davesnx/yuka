SWITCH ?=
BUILD_DIR ?= _build
PORT ?= 8080

DUNE = opam exec $(if $(SWITCH),--switch=$(SWITCH)) -- dune
export DUNE_BUILD_DIR = $(BUILD_DIR)

.PHONY: help
help: ## Print this help message
	@echo ""
	@echo "List of available make commands (SWITCH=<opam switch>, BUILD_DIR=$(BUILD_DIR), PORT=$(PORT))"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""

.PHONY: build
build: ## Build everything (native and Melange)
	$(DUNE) build --profile=dev

.PHONY: build-prod
build-prod: ## Build with --profile=release
	$(DUNE) build --profile=release

.PHONY: dev
dev: ## Build in watch mode
	$(DUNE) build -w --profile=dev

.PHONY: clean
clean: ## Clean artifacts
	$(DUNE) clean

.PHONY: test
test: ## Run all tests
	$(DUNE) build @runtest

.PHONY: test-watch
test-watch: ## Run all tests in watch mode
	$(DUNE) build @runtest -w

.PHONY: test-promote
test-promote: ## Run all tests and promote snapshots
	$(DUNE) build @runtest --auto-promote

.PHONY: ppx-test
ppx-test: ## Run ppx tests
	$(DUNE) build @test/ppx/runtest

.PHONY: ppx-test-watch
ppx-test-watch: ## Run ppx tests in watch mode
	$(DUNE) build @test/ppx/runtest -w

.PHONY: ppx-test-promote
ppx-test-promote: ## Run ppx tests and promote snapshots
	$(DUNE) build @test/ppx/runtest --auto-promote

.PHONY: demo-build
demo-build: ## Build the demo (server and client)
	$(DUNE) build --profile=dev @demo/all

.PHONY: demo-build-watch
demo-build-watch: ## Build the demo in watch mode
	$(DUNE) build --profile=dev @demo/all -w

.PHONY: demo-bundle
demo-bundle: demo-build ## Bundle the demo client with esbuild
	BUILD_DIR=$(BUILD_DIR) demo/bundle.sh

.PHONY: demo-serve
demo-serve: demo-build ## Serve the demo on PORT
	$(BUILD_DIR)/default/demo/server/demo_server.exe --port $(PORT)

.PHONY: demo-test
demo-test: ## Run the demo tests
	$(DUNE) build @demo/runtest --force

.PHONY: e2e
e2e: ## Browser check of the demo (native ES modules)
	BUILD_DIR=$(BUILD_DIR) e2e/run.sh

.PHONY: e2e-bundle
e2e-bundle: ## Browser check of the demo (esbuild bundle)
	BUILD_DIR=$(BUILD_DIR) BUNDLE=1 e2e/run.sh

.PHONY: bench
bench: ## Build and run the browser benchmark
	$(DUNE) build --profile=release @bench/bench
	node bench/run.ts $(BUILD_DIR)/default/bench/out

.PHONY: install-npm
install-npm: ## Install npm dependencies (esbuild, jsdom)
	npm install

.PHONY: init
init: install-npm ## Set up the dev environment
