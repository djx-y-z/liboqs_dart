# liboqs - Makefile
# Cross-platform build and development commands
#
# Usage: make <target> [ARGS="..."]
# Example: make build ARGS="macos --arch arm64"
# Example: make analyze ARGS="--fatal-infos"

.PHONY: help setup build regen check combine test analyze format format-check get clean version publish publish-dry-run

# Arguments are passed via ARGS variable
ARGS ?=

# Default target
.DEFAULT_GOAL := help

# =============================================================================
# Help
# =============================================================================

help:
	@echo ""
	@echo "liboqs - Available commands:"
	@echo ""
	@echo "  Pass arguments via ARGS variable: make <target> ARGS=\"...\""
	@echo ""
	@echo "  SETUP"
	@echo "    make setup                        - Install FVM and project Flutter version (run once)"
	@echo ""
	@echo "  BUILD"
	@echo "    make build ARGS=\"<platform>\"      - Build native libraries"
	@echo "                                        Platforms: macos, ios, android, linux, windows, all, list"
	@echo "                                        Example: make build ARGS=\"macos --arch arm64\""
	@echo ""
	@echo "  DEVELOPMENT"
	@echo "    make regen                        - Regenerate Dart FFI bindings from liboqs headers"
	@echo "    make check                        - Check for liboqs updates"
	@echo "                                        Example: make check ARGS=\"--update --version 0.16.0\""
	@echo "    make combine                      - Combine CI artifacts (used by GitHub Actions)"
	@echo ""
	@echo "  QUALITY ASSURANCE"
	@echo "    make test                         - Run tests"
	@echo "                                        Example: make test ARGS=\"test/kem_test.dart\""
	@echo "    make analyze                      - Run static analysis"
	@echo "                                        Example: make analyze ARGS=\"--fatal-infos\""
	@echo "    make format                       - Format Dart code"
	@echo "    make format-check                 - Check Dart code formatting"
	@echo ""
	@echo "  PUBLISHING"
	@echo "    make publish-dry-run              - Validate package before publishing"
	@echo "    make publish                      - Publish package (CI only, blocked locally)"
	@echo ""
	@echo "  UTILITIES"
	@echo "    make get                          - Get dependencies"
	@echo "    make clean                        - Clean build artifacts"
	@echo "    make version                      - Show current liboqs version"
	@echo "    make help                         - Show this help message"
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
	@touch .skip_liboqs_hook
	@fvm dart run scripts/build.dart $(ARGS); ret=$$?; rm -f .skip_liboqs_hook; exit $$ret

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
	fvm flutter analyze $(ARGS)

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
ifndef CI
	@echo ""
	@echo "ERROR: Local publishing is disabled."
	@echo ""
	@echo "This package uses automated publishing via GitHub Actions."
	@echo "To publish a new version:"
	@echo ""
	@echo "  1. Update version in pubspec.yaml"
	@echo "  2. Update CHANGELOG.md"
	@echo "  3. Commit and push changes"
	@echo "  4. Go to: https://github.com/djx-y-z/liboqs_dart/actions/workflows/publish.yml"
	@echo "  5. Click 'Run workflow'"
	@echo ""
	@echo "To validate the package locally, use: make publish-dry-run"
	@echo ""
	@exit 1
else
	fvm dart pub publish $(ARGS)
endif
