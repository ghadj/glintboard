# Single entry point for humans, CI, and coding agents. Uses only tools that ship with Xcode.
# Run `make` or `make help` to list targets.

PROJECT     := App.xcodeproj
SCHEME      := App
DERIVED     := .build/xcode
PACKAGE     := Packages/ScrapKit
# Extra flags, e.g. XCB_FLAGS="CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=" in CI,
# or SWIFT_TEST_FLAGS=--disable-sandbox inside Claude Code's sandbox.
XCB_FLAGS        ?=
SWIFT_TEST_FLAGS ?=

.DEFAULT_GOAL := help
.PHONY: help bootstrap test test-core test-app build run lint format check ci clean

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-11s %s\n", $$1, $$2}'

bootstrap: ## First-time setup: check tools, create local config, run core tests
	@scripts/bootstrap.sh

test-core: ## Fast package tests (run constantly)
	swift test --package-path $(PACKAGE) --parallel $(SWIFT_TEST_FLAGS)

test-app: ## App-level tests
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) $(XCB_FLAGS) test

test: test-core test-app ## All tests

build: ## Build the Debug app (the "Dev" variant)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) $(XCB_FLAGS) build

run: build ## Build and launch the Dev app
	open "$$(ls -d $(DERIVED)/Build/Products/Debug/*.app | head -1)"

lint: ## Check formatting
	xcrun swift-format lint --strict --recursive App Packages

format: ## Fix formatting in place
	xcrun swift-format format --in-place --recursive App Packages

check: lint ## Lint plus native-only and branding checks
	scripts/check-native-only.sh
	scripts/check-branding.sh

ci: check test ## Everything CI runs

clean: ## Remove build output
	rm -rf .build
