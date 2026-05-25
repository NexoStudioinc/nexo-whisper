# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build

.PHONY: all clean whisper setup build local local-release check healthcheck help dev run

# Default target
all: check build

# Development workflow
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" build

# Build for local DEV use without Apple Developer certificate.
# Incluye `LOCAL_BUILD` flag → arranca en estado .licensed (Pro) automáticamente.
# Útil para desarrollo y QA del lado dev. NO usar este DMG para distribución pública.
local: check setup
	@echo "Building VoiceInk for local DEV use (LOCAL_BUILD enabled → Pro by default)..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		build

# Build PARA DISTRIBUCIÓN PÚBLICA — sin LOCAL_BUILD flag.
# Resultado: app arranca en estado .free por default. Para activar Pro
# requiere license key real de Lemon Squeezy. Este es el DMG que va a
# GitHub Releases para que descarguen los usuarios.
#
# Misma config que `make local` excepto el `LOCAL_BUILD` flag y el destino
# del .app (con sufijo "-release" para no pisar el build dev).
local-release: check setup
	@echo "Building VoiceInk for PUBLIC release (no LOCAL_BUILD → .free by default)..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/VoiceInk.app" && \
	DEST="$$HOME/Downloads/Nexo Whisper Release.app" && \
	if [ -d "$$APP_PATH" ]; then \
		echo "Copying Nexo Whisper Release.app to ~/Downloads..."; \
		rm -rf "$$DEST"; \
		ditto "$$APP_PATH" "$$DEST"; \
		xattr -cr "$$DEST"; \
		echo ""; \
		echo "✅ Release build saved to: ~/Downloads/Nexo Whisper Release.app"; \
		echo "   Arranca en .free — para Pro requiere license key de LS."; \
		echo "   Empaquetar DMG con: create-dmg (ver BUILDING.md)"; \
	else \
		echo "Error: Could not find built VoiceInk.app at $$APP_PATH"; \
		exit 1; \
	fi
	@# NOTA: este target NO altera ~/Downloads/Nexo Whisper.app (build dev)
	@# para que puedas tener ambas versiones lado a lado.
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/VoiceInk.app" && \
	DEST="$$HOME/Downloads/Nexo Whisper.app" && \
	if [ -d "$$APP_PATH" ]; then \
		echo "Copying Nexo Whisper.app to ~/Downloads..."; \
		rm -rf "$$DEST"; \
		rm -rf "$$HOME/Downloads/VoiceInk.app"; \
		ditto "$$APP_PATH" "$$DEST"; \
		xattr -cr "$$DEST"; \
		echo ""; \
		echo "Build complete! App saved to: ~/Downloads/Nexo Whisper.app"; \
		echo "Run with: open \"$$HOME/Downloads/Nexo Whisper.app\""; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built VoiceInk.app at $$APP_PATH"; \
		exit 1; \
	fi

# Run application
# Prioriza el binario que produce `make local` (~/Downloads/Nexo Whisper.app).
# Fallbacks: el .app viejo con nombre VoiceInk.app por si quedó de un build
# anterior, y por último DerivedData de Xcode.
run:
	@if [ -d "$$HOME/Downloads/Nexo Whisper.app" ]; then \
		echo "Opening ~/Downloads/Nexo Whisper.app..."; \
		open "$$HOME/Downloads/Nexo Whisper.app"; \
	elif [ -d "$$HOME/Downloads/VoiceInk.app" ]; then \
		echo "Opening ~/Downloads/VoiceInk.app (legacy name)..."; \
		open "$$HOME/Downloads/VoiceInk.app"; \
	else \
		echo "Looking for VoiceInk.app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "VoiceInk.app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "Nexo Whisper.app not found. Please run 'make local' first."; \
			exit 1; \
		fi; \
	fi

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to VoiceInk project"
	@echo "  build              Build the VoiceInk Xcode project"
	@echo "  local              Build for local use (no Apple Developer certificate needed)"
	@echo "  run                Launch the built VoiceInk app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"