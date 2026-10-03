# Single entry point for humans, CI, and coding agents. Uses only tools that ship with Xcode.
# Run `make` or `make help` to list targets.
#
# Build, test, check, bootstrap, and perf runs also save their output to .build/logs/ and a
# summary to .build/logs/summary.md (scripts/logged.sh), so an agent can read results of
# runs made in Terminal.

PROJECT     := App.xcodeproj
SCHEME      := App
DERIVED     := .build/xcode
PACKAGE     := Packages/ScrapKit
LOGGED      := scripts/logged.sh
# One id per `make` invocation (sub-makes inherit it), so .build/logs/summary.md can tell
# this run's targets from earlier ones.
ifndef LOG_RUN
LOG_RUN := $(shell date +%Y%m%d-%H%M%S)-$(shell echo $$PPID)
endif
export LOG_RUN
# Extra flags, e.g. XCB_FLAGS="CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=" in CI.
XCB_FLAGS        ?=
PERF_FLAGS       ?=
SWIFT_TEST_FLAGS ?=

.DEFAULT_GOAL := help
.PHONY: help bootstrap test test-core test-app build run lint format check _check perf ci clean

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-11s %s\n", $$1, $$2}'

bootstrap: ## First-time setup: check tools, create local config, run core tests
	@SWIFT_TEST_FLAGS="$(SWIFT_TEST_FLAGS)" $(LOGGED) bootstrap scripts/bootstrap.sh

test-core: ## Fast package tests (run constantly)
	@$(LOGGED) test-core swift test --package-path $(PACKAGE) --parallel $(SWIFT_TEST_FLAGS)

test-app: ## App-level tests
	@$(LOGGED) test-app xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) $(XCB_FLAGS) test

test: test-core test-app ## All tests

build: ## Build the Debug app (the "Dev" variant)
	@$(LOGGED) build xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) $(XCB_FLAGS) build

run: build ## Build and launch the Dev app
	open "$$(ls -d $(DERIVED)/Build/Products/Debug/*.app | head -1)"

lint: ## Check formatting
	xcrun swift-format lint --strict --recursive App Packages
	@echo "lint passed"

format: ## Fix formatting in place
	xcrun swift-format format --in-place --recursive App Packages

check: ## Lint plus native-only, branding, and layering checks, and their self-test
	@$(LOGGED) check $(MAKE) --no-print-directory _check

_check: lint
	scripts/check-native-only.sh
	scripts/check-branding.sh
	scripts/check-layering.sh
	scripts/test-checks.sh

perf: ## Measure the Release baseline (NFR-2, NFR-4); e.g. PERF_FLAGS="--milestone M1 --record"
	@XCB_FLAGS="$(XCB_FLAGS)" $(LOGGED) perf scripts/measure-baseline.sh $(PERF_FLAGS)

ci: check test ## Everything CI runs

clean: ## Remove build output
	rm -rf .build
