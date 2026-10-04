.PHONY: project open build test check install-cli

DESTINATION := platform=macOS,arch=arm64
BINDIR ?= /opt/homebrew/bin

project: ## Regenerate Vortex.xcodeproj from project.yml
	xcodegen generate

open: project ## Regenerate and open in Xcode
	open Vortex.xcodeproj

build: ## Compile the app without signing (for checks)
	xcodebuild -project Vortex.xcodeproj -scheme Vortex -configuration Debug -destination "$(DESTINATION)" CODE_SIGNING_ALLOWED=NO -skipMacroValidation -quiet build

test: ## Run package tests
	swift test --package-path Packages

check: ## No network APIs outside Secrets
	./scripts/check-no-network.sh

install-cli: ## Link the vortex command into BINDIR (default /opt/homebrew/bin)
	ln -sf "$(CURDIR)/Tools/CLI/vortex" "$(BINDIR)/vortex"
