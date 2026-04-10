.PHONY: build install uninstall clean release notarize

APP_NAME := ClaudeWatch
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR := /Applications

build:
	@chmod +x build.sh
	@./build.sh

install: build
	@cp -R $(APP_BUNDLE) $(INSTALL_DIR)/
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

uninstall:
	@rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	@echo "Uninstalled $(APP_NAME).app"

clean:
	@rm -rf $(BUILD_DIR)
	@echo "Cleaned build directory"

# Create a release zip with SHA-256 checksum
release: build
	@cd $(BUILD_DIR) && zip -r ../$(APP_NAME).zip $(APP_NAME).app
	@shasum -a 256 $(APP_NAME).zip
	@echo "\nRelease artifact: $(APP_NAME).zip"

# Sign with Developer ID (requires Apple Developer account)
# Usage: make sign IDENTITY="Developer ID Application: Your Name (TEAMID)"
sign: build
	@if [ -z "$(IDENTITY)" ]; then \
		echo "Usage: make sign IDENTITY=\"Developer ID Application: Your Name (TEAMID)\""; \
		exit 1; \
	fi
	codesign --force --sign "$(IDENTITY)" --options runtime $(APP_BUNDLE)
	@echo "Signed with: $(IDENTITY)"

# Notarize (requires signing first)
# Usage: make notarize APPLE_ID="you@example.com" TEAM_ID="XXXXXXXXXX"
notarize: release
	@if [ -z "$(APPLE_ID)" ] || [ -z "$(TEAM_ID)" ]; then \
		echo "Usage: make notarize APPLE_ID=\"you@example.com\" TEAM_ID=\"XXXXXXXXXX\""; \
		exit 1; \
	fi
	xcrun notarytool submit $(APP_NAME).zip \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(TEAM_ID)" \
		--wait
	xcrun stapler staple $(APP_BUNDLE)
	@echo "Notarization complete"
