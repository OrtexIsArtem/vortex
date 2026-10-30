.PHONY: project open build install test check hooks install-cli

DESTINATION := platform=macOS,arch=arm64
BINDIR ?= /opt/homebrew/bin

project: ## Regenerate Vortex.xcodeproj from project.yml
	xcodegen generate

open: project ## Regenerate and open in Xcode
	open Vortex.xcodeproj

build: ## Compile the app without signing (for checks), into build/ and under a bundle id of its own, so nothing opens it for the signed app
	xcodebuild -project Vortex.xcodeproj -scheme Vortex -configuration Debug -destination "$(DESTINATION)" -derivedDataPath build/DerivedData PRODUCT_BUNDLE_IDENTIFIER=io.github.ortexisartem.vortex.check CODE_SIGNING_ALLOWED=NO -skipMacroValidation -quiet build

# The team in Config/Local.xcconfig signs `make install`. Without one, or with the example's placeholder, the build
# is signed ad hoc.
TEAM := $(filter-out ABCDE12345,$(shell sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM(\[config=Release\])?[[:space:]]*=[[:space:]]*([A-Z0-9]{10}).*/\2/p' Config/Local.xcconfig 2>/dev/null | head -1))
INSTALL_SIGNING := $(if $(TEAM),,CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
INSTALL_DIR ?= /Applications
BUILT_APP := build/Release/Build/Products/Release/Vortex.app

install: ## Build a release, put it in /Applications and open it: for daily use, unlike a debug run from Xcode
	xcodebuild -project Vortex.xcodeproj -scheme Vortex -configuration Release -destination "$(DESTINATION)" -derivedDataPath build/Release ARCHS=arm64 $(INSTALL_SIGNING) -skipMacroValidation -quiet build
	@[ -n "$(TEAM)" ] || echo "No team in Config/Local.xcconfig: signed ad hoc, so macOS asks for Vortex's permissions again after each rebuild."
	@set -e; app="$(INSTALL_DIR)/Vortex.app"; \
	id=$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$(BUILT_APP)/Contents/Info.plist"); \
	if [ -e "$$app" ]; then \
	  old=$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$$app/Contents/Info.plist" 2>/dev/null || true); \
	  if [ "$$old" != "$$id" ]; then echo "$$app is not this Vortex ($$old), so it stays; remove it yourself." >&2; exit 1; fi; \
	fi; \
	rm -rf "$$app.new"; ditto "$(BUILT_APP)" "$$app.new"; rm -rf "$$app"; mv "$$app.new" "$$app"; open -n "$$app"

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
