SWITCH ?= $(shell d="$(CURDIR)"; while [ "$$d" != / ]; do [ -d "$$d/_opam" ] && { echo "$$d"; break; }; d=$$(dirname "$$d"); done)
BUILD_DIR ?= _build
PORT ?= 8080
OCAML_VERSION ?= 5.5.2

DUNE = opam exec $(if $(SWITCH),--switch=$(SWITCH)) -- dune
export DUNE_BUILD_DIR = $(BUILD_DIR)
export DUNE_ROOT = $(CURDIR)

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
	BUILD_DIR=$(BUILD_DIR) demo/mini-linear/bundle.sh

.PHONY: demo-serve
demo-serve: demo-build ## Serve the demo on PORT
	$(BUILD_DIR)/default/demo/mini-linear/server/demo_server.exe --port $(PORT) --base /mini-linear

.PHONY: demo-dev
demo-dev: ## Run the demo under yuka dev: rebuild, restart and reload the browser on change (PORT)
	$(DUNE) build --profile=dev ./gen/yuka_cli.exe
	opam exec $(if $(SWITCH),--switch=$(SWITCH)) -- $(BUILD_DIR)/default/gen/yuka_cli.exe dev \
	  --build 'dune build --watch --profile=dev @demo/all' \
	  --assets $(BUILD_DIR)/default/demo/mini-linear/static --assets $(BUILD_DIR)/default/demo/mini-linear/client/out \
	  -- $(BUILD_DIR)/default/demo/mini-linear/server/demo_server.exe --port $(PORT) --base /mini-linear

.PHONY: demo-test
demo-test: ## Run the demo tests
	$(DUNE) build @demo/runtest --force

.PHONY: e2e
e2e: ## Browser check of the demo (native ES modules)
	SWITCH=$(SWITCH) BUILD_DIR=$(BUILD_DIR) e2e/run.sh

.PHONY: e2e-bundle
e2e-bundle: ## Browser check of the demo (esbuild bundle)
	SWITCH=$(SWITCH) BUILD_DIR=$(BUILD_DIR) BUNDLE=1 e2e/run.sh

.PHONY: e2e-shared
e2e-shared: ## Two server processes on one database (YUKA_DEMO_DATABASE): a change through one shows on the other
	SWITCH=$(SWITCH) BUILD_DIR=$(BUILD_DIR) e2e/shared_store.sh

.PHONY: bench
bench: ## Build and run the browser benchmark
	$(DUNE) build --profile=release @bench/bench
	node bench/run.ts $(BUILD_DIR)/default/bench/out

BENCH_RUNS ?= 10
BENCH_OUT ?= $(BUILD_DIR)/bench-keyed/result.json
BENCH_APPS ?= vanillajs,solid,yuka

.PHONY: bench-keyed
bench-keyed: ## Run the keyed table benchmark: yuka, solid, vanillajs (BENCH_RUNS, BENCH_OUT, BENCH_APPS, CHROME_PATH)
	$(DUNE) build --profile=release @bench/keyed/bench-keyed
	BUILD_DIR=$(BUILD_DIR) bench/keyed/build.sh
	node bench/keyed/run.ts --site $(BUILD_DIR)/bench-keyed --runs $(BENCH_RUNS) --apps $(BENCH_APPS) --out $(BENCH_OUT)

.PHONY: size
size: ## Bundle the keyed benchmark app, the demo and three one-island pages, print raw and gzip bytes and the JavaScript each page loads at start, check the budget in bench/size/budget.json
	$(DUNE) build --profile=release @bench/keyed/bench-keyed @demo/all @bench/size/page/client/size-page @bench/size/codec_page/client/size-codec-page @bench/size/remote_page/client/size-remote-page
	node bench/size/size.ts --build-dir $(BUILD_DIR)

SSR_ROWS ?= 100
SSR_CONNECTIONS ?= 32
SSR_ARGS ?=

.PHONY: bench-ssr
bench-ssr: ## SSR throughput of the same issue list page: yuka, dream, server-reason-react, react, solid (SSR_ROWS, SSR_CONNECTIONS, SSR_ARGS)
	$(DUNE) build --profile=release @bench/ssr/ocaml/all
	[ -d bench/ssr/node/node_modules ] || npm ci --prefix bench/ssr/node --no-audit --no-fund
	node bench/ssr/run.ts --build-dir $(BUILD_DIR) --rows $(SSR_ROWS) --connections $(SSR_CONNECTIONS) $(SSR_ARGS)

PAGES_RUNS ?= 5
PAGES_THROTTLE ?= 4

.PHONY: measure-pages
measure-pages: demo-bundle ## Measure JS bytes, TBT and LCP of each demo page, and LCP as plain HTML (PAGES_RUNS, PAGES_THROTTLE, CHROME_PATH)
	node bench/pages/measure.ts --build-dir $(BUILD_DIR) --runs $(PAGES_RUNS) --throttle $(PAGES_THROTTLE)

BENCH_CHECKS ?= keyed,ssr,pages

.PHONY: bench-check
bench-check: ## Check the last bench-keyed, bench-ssr and measure-pages results against bench/gate/limits.json (BENCH_CHECKS)
	node bench/gate/gate.ts --build-dir $(BUILD_DIR) --keyed $(BENCH_OUT) --checks $(BENCH_CHECKS)

.PHONY: bench-gate
bench-gate: ## Run bench-keyed (yuka and solid), bench-ssr (yuka-stream and its references, interleaved) and measure-pages, then bench-check
	$(MAKE) bench-keyed BENCH_APPS=solid,yuka
	$(MAKE) bench-ssr SSR_ARGS="--only yuka-stream,solid-node,server-reason-react --interleave"
	$(MAKE) measure-pages
	$(MAKE) bench-check

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
install: ## Install the opam dependencies, the dev packages and the editor tools
	opam update
	opam install . --deps-only --with-test --with-doc -y
	opam install -y $(DEV_PACKAGES) ocaml-lsp-server ocamlmerlin-mlx ocamlformat ocamlformat-mlx

# server-reason-react is out until quickjs supports dune 3.25: see bench/ssr/ocaml/dune
DEV_PACKAGES = cmarkit ochre tm-grammars jsonkit

.PHONY: dev-packages
dev-packages: ## List opam packages the benchmarks and the demo need that are not in the opam files
	@echo "$(DEV_PACKAGES)"

# dune 3.25.0 with https://github.com/ocaml/dune/pull/16699, 16939 and 16941; Melange 7.0.1-55 with
# https://github.com/melange-re/melange/pull/2211, for https://github.com/ocaml/dune/issues/17020; ochre with
# https://github.com/davesnx/ochre/pull/6, which ochre 1.1.0 lacks: its Oniguruma stubs return wrong matches after a GC
.PHONY: pin-list
pin-list: ## List pinned dependencies, one "<name> <target>" per line
	@echo "ache git+https://github.com/davesnx/ache.git#5827338a3c35d39feec2f772a7cc4014ebef7a7c"
	@echo "ache-lwt git+https://github.com/davesnx/ache.git#5827338a3c35d39feec2f772a7cc4014ebef7a7c"
	@echo "cows git+https://github.com/syaiful6/cows.git#fc74ab9f372adf6b19d00feec60e4bc669ea10a8"
	@echo "dune.3.25.0 git+https://github.com/davesnx/dune.git#1e6f26d4d6615e0d2770977a00d2f654fcc4dba3"
	@echo "melange.7.0.1-55 git+https://github.com/davesnx/melange.git#16162e70268bf63cab1e12fd14f49f8d06983cf6"
	@echo "ochre git+https://github.com/davesnx/ochre.git#2bd2255d631ce03746efee2018fcfbc171abb42f"
	@echo "sch git+https://github.com/syaiful6/tapak.git#874cb1b6e1b54019d3425550d8c471621aa59f17"
	@echo "tapak git+https://github.com/syaiful6/tapak.git#874cb1b6e1b54019d3425550d8c471621aa59f17"

.PHONY: pin
pin: ## Pin dependencies
	@$(MAKE) -s pin-list | while read -r name target; do \
		opam pin add "$$name" "$$target" --yes --no-action || exit 1; \
	done
