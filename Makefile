SWITCH ?= $(shell d="$(CURDIR)"; while [ "$$d" != / ]; do [ -d "$$d/_opam" ] && { echo "$$d"; break; }; d=$$(dirname "$$d"); done)
BUILD_DIR ?= _build
PORT ?= 8080
OCAML_VERSION ?= 5.4.1

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
	$(DUNE) build --root . --profile=dev

.PHONY: build-prod
build-prod: ## Build with --profile=release
	$(DUNE) build --root . --profile=release

.PHONY: dev
dev: ## Build in watch mode
	$(DUNE) build --root . -w --profile=dev

.PHONY: clean
clean: ## Clean artifacts
	$(DUNE) clean --root .

.PHONY: test
test: ## Run all tests
	$(DUNE) build --root . @runtest

.PHONY: test-watch
test-watch: ## Run all tests in watch mode
	$(DUNE) build --root . @runtest -w

.PHONY: test-promote
test-promote: ## Run all tests and promote snapshots
	$(DUNE) build --root . @runtest --auto-promote

.PHONY: ppx-test
ppx-test: ## Run ppx tests
	$(DUNE) build --root . @test/ppx/runtest

.PHONY: ppx-test-watch
ppx-test-watch: ## Run ppx tests in watch mode
	$(DUNE) build --root . @test/ppx/runtest -w

.PHONY: ppx-test-promote
ppx-test-promote: ## Run ppx tests and promote snapshots
	$(DUNE) build --root . @test/ppx/runtest --auto-promote

.PHONY: demo-build
demo-build: ## Build the demo (server and client)
	$(DUNE) build --root . --profile=dev @demo/all

.PHONY: demo-build-watch
demo-build-watch: ## Build the demo in watch mode
	$(DUNE) build --root . --profile=dev @demo/all -w

.PHONY: demo-bundle
demo-bundle: demo-build ## Bundle the demo client with esbuild
	BUILD_DIR=$(BUILD_DIR) demo/bundle.sh

.PHONY: demo-serve
demo-serve: demo-build ## Serve the demo on PORT
	$(BUILD_DIR)/default/demo/server/demo_server.exe --port $(PORT)

.PHONY: demo-dev
demo-dev: ## Run the demo under yuka dev: rebuild, restart and reload the browser on change (PORT)
	$(DUNE) build --root . --profile=dev ./gen/yuka_cli.exe
	opam exec $(if $(SWITCH),--switch=$(SWITCH)) -- $(BUILD_DIR)/default/gen/yuka_cli.exe dev \
	  --build 'dune build --root . --watch --profile=dev @demo/all' \
	  --assets $(BUILD_DIR)/default/demo/static --assets $(BUILD_DIR)/default/demo/client/out \
	  -- $(BUILD_DIR)/default/demo/server/demo_server.exe --port $(PORT)

.PHONY: demo-test
demo-test: ## Run the demo tests
	$(DUNE) build --root . @demo/runtest --force

.PHONY: e2e
e2e: ## Browser check of the demo (native ES modules)
	SWITCH=$(SWITCH) BUILD_DIR=$(BUILD_DIR) e2e/run.sh

.PHONY: e2e-bundle
e2e-bundle: ## Browser check of the demo (esbuild bundle)
	SWITCH=$(SWITCH) BUILD_DIR=$(BUILD_DIR) BUNDLE=1 e2e/run.sh

.PHONY: bench
bench: ## Build and run the browser benchmark
	$(DUNE) build --root . --profile=release @bench/bench
	node bench/run.ts $(BUILD_DIR)/default/bench/out

BENCH_RUNS ?= 10
BENCH_OUT ?= $(BUILD_DIR)/bench-keyed/result.json

.PHONY: bench-keyed
bench-keyed: ## Run the keyed table benchmark: yuka, solid, vanillajs (BENCH_RUNS, BENCH_OUT, CHROME_PATH)
	$(DUNE) build --root . --profile=release @bench/keyed/bench-keyed
	BUILD_DIR=$(BUILD_DIR) bench/keyed/build.sh
	node bench/keyed/run.ts --site $(BUILD_DIR)/bench-keyed --runs $(BENCH_RUNS) --out $(BENCH_OUT)

.PHONY: size
size: ## Bundle the keyed benchmark app, the demo and three one-island pages, print raw and gzip bytes and the JavaScript each page loads at start, check the budget in bench/size/budget.json
	$(DUNE) build --root . --profile=release @bench/keyed/bench-keyed @demo/all @bench/size/page/client/size-page @bench/size/codec_page/client/size-codec-page @bench/size/remote_page/client/size-remote-page
	node bench/size/size.ts --build-dir $(BUILD_DIR)

SSR_ROWS ?= 100
SSR_CONNECTIONS ?= 32

.PHONY: bench-ssr
bench-ssr: ## SSR throughput of the same issue list page: yuka, dream, server-reason-react, react, solid (SSR_ROWS, SSR_CONNECTIONS)
	$(DUNE) build --root . --profile=release @bench/ssr/ocaml/all
	[ -d bench/ssr/node/node_modules ] || npm ci --prefix bench/ssr/node --no-audit --no-fund
	node bench/ssr/run.ts --build-dir $(BUILD_DIR) --rows $(SSR_ROWS) --connections $(SSR_CONNECTIONS)

PAGES_RUNS ?= 5
PAGES_THROTTLE ?= 4

.PHONY: measure-pages
measure-pages: demo-bundle ## Measure JS bytes, TBT and LCP of each demo page, and LCP as plain HTML (PAGES_RUNS, PAGES_THROTTLE, CHROME_PATH)
	node bench/pages/measure.ts --build-dir $(BUILD_DIR) --runs $(PAGES_RUNS) --throttle $(PAGES_THROTTLE)

.PHONY: docs
docs: ## Copy docs/ to the references of the agent skill in skills/yuka (make test fails when they differ)
	rm -rf skills/yuka/references
	cp -r docs skills/yuka/references

.PHONY: install-npm
install-npm: ## Install npm dependencies (esbuild, jsdom)
	npm install

.PHONY: system-deps
system-deps: ## Install system packages: libpq for the Postgres live bus (sudo apt-get on Debian/Ubuntu, brew on macOS)
	@if [ "$$(uname)" = Darwin ]; then \
		brew install libpq pkg-config; \
	else \
		sudo apt-get install -y libpq-dev pkg-config; \
	fi

.PHONY: create-switch
create-switch: ## Create a local opam switch in _opam (OCAML_VERSION)
	opam switch create . ocaml-base-compiler.$(OCAML_VERSION) --no-install -y

pin install: export OPAMSWITCH = $(CURDIR)

ifeq ($(shell uname),Darwin)
install: export PKG_CONFIG_PATH := $(shell brew --prefix libpq)/lib/pkgconfig:$(PKG_CONFIG_PATH)
endif

.PHONY: init
init: system-deps create-switch pin install install-npm ## Set up the dev environment: system packages, local switch, opam and npm dependencies

.PHONY: install
install: ## Install the opam dependencies, the dev packages, ocaml-lsp-server and the mlx reader for it
	opam update
	opam install . --deps-only --with-test --with-doc -y
	opam install -y $(DEV_PACKAGES) ocaml-lsp-server ocamlmerlin-mlx

# server-reason-react is out until quickjs supports dune 3.25: see bench/ssr/ocaml/dune
DEV_PACKAGES = cmarkit ochre tm-grammars

.PHONY: dev-packages
dev-packages: ## List opam packages the benchmarks and the demo need that are not in the opam files
	@echo "$(DEV_PACKAGES)"

.PHONY: pin-list
pin-list: ## List pinned dependencies, one "<name> <target>" per line
	@echo "melange git+https://github.com/jongleb/melange#7c961fbdfebac142347fa2e924e0957cd97e6d53"

.PHONY: pin
pin: ## Pin dependencies
	@$(MAKE) -s pin-list | while read -r name target; do \
		opam pin add "$$name" "$$target" --yes --no-action || exit 1; \
	done
