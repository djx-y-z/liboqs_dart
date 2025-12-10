# liboqs - Makefile
# Cross-platform build and development commands
#
# Usage: make <target> [args]
# Example: make build macos --arch arm64

.PHONY: help setup build regen check combine test analyze format get clean version publish publish-dry-run

# Capture all arguments after the target
ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
# Prevent make from treating args as targets
$(eval $(ARGS):;@:)

# Default target
.DEFAULT_GOAL := help

# =============================================================================
# Help
# =============================================================================

help:
	@echo ""
	@echo "liboqs - Available commands:"
	@echo ""
	@echo "  SETUP"
	@echo "    make setup                       - Install FVM and project Flutter version (run once)"
	@echo ""
	@echo "  BUILD"
	@echo "    make build <platform> [options]  - Build native libraries"
	@echo "                                       Platforms: macos, ios, android, linux, windows, all, list"
	@echo "                                       Example: make build macos --arch arm64"
	@echo ""
	@echo "  DEVELOPMENT"
	@echo "    make regen                       - Regenerate Dart FFI bindings from liboqs headers"
	@echo "    make check [options]             - Check for liboqs updates"
	@echo "                                       Options: --update, --version X.Y.Z, --json"
	@echo "    make combine                     - Combine CI artifacts (used by GitHub Actions)"
	@echo ""
	@echo "  QUALITY ASSURANCE"
	@echo "    make test [path]                 - Run tests (optionally specific test file)"
	@echo "    make analyze                     - Run static analysis"
	@echo "    make format                      - Format Dart code"
	@echo "    make format-check                - Check Dart code formatting"
	@echo ""
	@echo "  PUBLISHING"
	@echo "    make publish-dry-run             - Validate package before publishing"
	@echo "    make publish                     - Publish package to pub.dev"
	@echo ""
	@echo "  UTILITIES"
	@echo "    make get                         - Get dependencies"
	@echo "    make clean                       - Clean build artifacts"
	@echo "    make version                     - Show current liboqs version"
	@echo "    make help                        - Show this help message"
	@echo ""

# =============================================================================
# Setup
# =============================================================================

setup:
	@echo "Installing FVM (Flutter Version Management)..."
	dart pub global activate fvm
	@echo ""
	@echo "Installing project Flutter version..."
	fvm install
	@echo ""
	@echo "Getting dependencies..."
	fvm dart pub get --no-example
	@echo ""
	@echo "Setup complete! You can now use 'make help' to see available commands."

# =============================================================================
# Build
# =============================================================================

build:
	fvm dart run scripts/build.dart $(ARGS)

# =============================================================================
# Development
# =============================================================================

regen:
	fvm dart run scripts/regenerate_bindings.dart $(ARGS)

check:
	fvm dart run scripts/check_updates.dart $(ARGS)

combine:
	fvm dart run scripts/combine_artifacts.dart $(ARGS)

# =============================================================================
# Quality Assurance
# =============================================================================

test:
	fvm dart test $(ARGS)

analyze:
	fvm dart analyze $(ARGS)

format:
	fvm dart format . $(ARGS)

format-check:
	fvm dart format --set-exit-if-changed . $(ARGS)

# =============================================================================
# Utilities
# =============================================================================

get:
	fvm dart pub get --no-example

clean:
	rm -rf .dart_tool build
	fvm dart pub get --no-example

version:
	@cat LIBOQS_VERSION

# =============================================================================
# Publishing
# =============================================================================

publish-dry-run:
	fvm dart pub publish --dry-run

publish:
	fvm dart pub publish
