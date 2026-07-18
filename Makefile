# liboqs - Makefile
# Cross-platform build and development commands
#
# Usage: make <target> [ARGS="..."]
# Example: make build ARGS="macos --arch arm64"
# Example: make analyze ARGS="--fatal-infos"
#
# On Windows CI (Git Bash), use cmd to run fvm.bat from PATH:
# Example: make build ARGS="windows" FVM="cmd //c fvm"

.PHONY: help setup setup-repo-protections build regen check combine test coverage analyze format format-check get clean version get-version get-build get-full-version check-release doc publish publish-dry-run update-changelog release release-native

# FVM command - can be overridden to provide full path on Windows CI
FVM ?= fvm

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
	@echo "    make setup-repo-protections       - Apply GitHub rulesets + native-build env (one-time, needs gh admin)"
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
	@echo "    make update-changelog             - Update CHANGELOG.md with AI (liboqs update entry)"
	@echo "                                        Example: make update-changelog ARGS=\"--version 0.17.0 --from 0.16.0\""
	@echo ""
	@echo "  QUALITY ASSURANCE"
	@echo "    make test                         - Run tests"
	@echo "                                        Example: make test ARGS=\"test/kem_test.dart\""
	@echo "    make coverage                     - Run tests with coverage report"
	@echo "    make analyze                      - Run static analysis"
	@echo "                                        Example: make analyze ARGS=\"--fatal-infos\""
	@echo "    make format                       - Format Dart code"
	@echo "    make format-check                 - Check Dart code formatting"
	@echo "    make check-targets                - Check deployment target consistency (iOS/macOS)"
	@echo "                                        Example: make check-targets ARGS=\"--update\""
	@echo "    make doc                          - Generate API documentation"
	@echo ""
	@echo "  PUBLISHING"
	@echo "    make release-native               - Release native libraries (signed tag liboqs-<fullVersion>, triggers CI build)"
	@echo "    make release                      - Release the package (bump, finalize CHANGELOG, tag, push)"
	@echo "                                        Example: make release ARGS=\"--version 2.0.1\""
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
	$(FVM) install
	@echo ""
	@echo "Getting dependencies..."
	$(FVM) dart pub get --no-example
	@echo ""
	@echo "Configuring git hooks..."
	git config core.hooksPath .githooks
	@echo ""
	@echo "Setup complete! You can now use 'make help' to see available commands."

# Apply the committed repository rulesets (.github/rulesets/*.json) and the
# native-build environment to the GitHub repo via `gh` (one-time; run after the
# GitHub repo exists). Idempotent by ruleset name; needs `gh` as a repo admin.
#   make setup-repo-protections                  # apply (skips existing rulesets)
#   make setup-repo-protections ARGS="--update"  # overwrite existing rulesets
setup-repo-protections:
	@$(FVM) dart scripts/setup_repo_protections.dart $(ARGS)

# =============================================================================
# Build
# =============================================================================

build:
	@touch .skip_liboqs_hook
	@$(FVM) dart run scripts/build.dart $(ARGS); ret=$$?; rm -f .skip_liboqs_hook; exit $$ret

# =============================================================================
# Development
# =============================================================================

regen:
	@touch .skip_liboqs_hook
	@$(FVM) dart run scripts/regenerate_bindings.dart $(ARGS); ret=$$?; rm -f .skip_liboqs_hook; exit $$ret

check:
	@touch .skip_liboqs_hook
	@$(FVM) dart run scripts/check_updates.dart $(ARGS); ret=$$?; rm -f .skip_liboqs_hook; exit $$ret

update-changelog:
	@$(FVM) dart scripts/update_changelog.dart $(ARGS)

combine:
	@touch .skip_liboqs_hook
	@$(FVM) dart run scripts/combine_artifacts.dart $(ARGS); ret=$$?; rm -f .skip_liboqs_hook; exit $$ret

# =============================================================================
# Quality Assurance
# =============================================================================

test:
	$(FVM) dart test $(ARGS)

coverage:
	$(FVM) dart test --coverage=coverage
	$(FVM) dart run coverage:format_coverage --check-ignore --lcov --in=coverage --out=coverage/lcov.info --report-on=lib
	lcov --remove coverage/lcov.info 'lib/src/bindings/*' -o coverage/lcov.info
	lcov --summary coverage/lcov.info

analyze:
	$(FVM) flutter analyze $(ARGS)

format:
	$(FVM) dart format . $(ARGS)

format-check:
	$(FVM) dart format --set-exit-if-changed . $(ARGS)

check-targets:
	@$(FVM) dart scripts/check_deployment_targets.dart $(ARGS)

doc:
	rm -rf doc
	$(FVM) dart doc $(ARGS)
	@echo ""
	@echo "Documentation generated in doc/api/"
	@echo "Open doc/api/index.html to view locally"

# =============================================================================
# Utilities
# =============================================================================

get:
	$(FVM) dart pub get --no-example

clean:
	rm -rf .dart_tool build
	$(FVM) dart pub get --no-example

version:
	@$(FVM) dart run scripts/get_version.dart

# Internal target for getting version in scripts (outputs only the value)
get-version:
	@$(FVM) dart run scripts/get_version.dart --field version

get-build:
	@$(FVM) dart run scripts/get_version.dart --field build

get-full-version:
	@$(FVM) dart run scripts/get_version.dart --field full

check-release:
	@touch .skip_liboqs_hook
	@$(FVM) dart run scripts/check_release.dart $(ARGS); ret=$$?; rm -f .skip_liboqs_hook; exit $$ret

# =============================================================================
# Publishing
# =============================================================================

# Release the native libraries: signed tag `liboqs-<fullVersion>` on
# origin/main, pushed — triggers build-liboqs.yml. Run AFTER the version-bump
# PR merged (merging alone no longer builds). Commits nothing.
#   Example: make release-native
release-native:
	@$(FVM) dart scripts/release_native.dart $(ARGS)

release:
	@$(FVM) dart scripts/release.dart $(ARGS)

publish-dry-run:
	$(FVM) dart pub publish --dry-run

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
	@echo "  4. Create and push a tag: git tag v1.0.1 && git push origin v1.0.1"
	@echo "  5. GitHub Actions will automatically publish to pub.dev"
	@echo ""
	@echo "To validate the package locally, use: make publish-dry-run"
	@echo ""
	@exit 1
else
	$(FVM) dart pub publish $(ARGS)
endif
