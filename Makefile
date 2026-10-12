.PHONY: project open build test check hooks install-cli

DESTINATION := platform=macOS,arch=arm64
BINDIR ?= /opt/homebrew/bin

project: ## Regenerate Vortex.xcodeproj from project.yml
	xcodegen generate

open: project ## Regenerate and open in Xcode
	open Vortex.xcodeproj

build: ## Compile the app without signing (for checks), into build/ and under a bundle id of its own, so nothing opens it for the signed app
	xcodebuild -project Vortex.xcodeproj -scheme Vortex -configuration Debug -destination "$(DESTINATION)" -derivedDataPath build/DerivedData PRODUCT_BUNDLE_IDENTIFIER=io.github.ortexisartem.vortex.check CODE_SIGNING_ALLOWED=NO -skipMacroValidation -quiet build

test: ## Run package tests
	swift test --package-path Packages

check: ## No network APIs or commands outside Secrets
	./scripts/check-no-network.sh

hooks: ## Run the check and the package tests before every push
	rm -f "$$(git rev-parse --git-path hooks)/pre-push"
	printf '#!/bin/sh\nexec "$$(git rev-parse --show-toplevel)/scripts/pre-push" "$$@"\n' > "$$(git rev-parse --git-path hooks)/pre-push"
	chmod +x "$$(git rev-parse --git-path hooks)/pre-push"

install-cli: ## Link the vortex command into BINDIR (default /opt/homebrew/bin)
	ln -sf "$(CURDIR)/Tools/CLI/vortex" "$(BINDIR)/vortex"
