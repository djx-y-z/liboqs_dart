# liboqs - Makefile
# Cross-platform build and development commands
#
# Usage: make <target> [ARGS="..."]
# Example: make build ARGS="macos --arch arm64"
# Example: make analyze ARGS="--fatal-infos"
#
# On Windows CI (Git Bash), use cmd to run fvm.bat from PATH:
# Example: make build ARGS="windows" FVM="cmd //c fvm"

.PHONY: help setup setup-repo-protections build regen check combine test coverage analyze format format-check check-targets third-party-notices verify-third-party-notices check-action-pins lint-workflows get clean version get-version get-build get-full-version check-release doc publish publish-dry-run update-changelog release release-native

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
	@echo "    make third-party-notices          - Regenerate THIRD_PARTY_NOTICES.txt from the liboqs sources"
	@echo "    make verify-third-party-notices   - Verify THIRD_PARTY_NOTICES.txt is up to date"
	@echo "    make lint-workflows               - Lint GitHub Actions workflows (actionlint + shellcheck)"
	@echo "    make check-action-pins            - Verify every third-party action ref exists (needs gh)"
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

# Regenerate the third-party notice inventory for the shipped native library.
# Run after every liboqs version bump; CI verifies the committed file matches
# the pinned sources, and both release stages refuse to proceed without it.
third-party-notices:
	@$(FVM) dart scripts/generate_third_party_notices.dart $(ARGS)

verify-third-party-notices:
	@$(FVM) dart scripts/generate_third_party_notices.dart --check

# Resolve every third-party `uses:` in .github against the GitHub API. This is
# the check actionlint cannot do: it is offline, and on a ref its bundled
# snapshot does not know it silently turns its checks off rather than reporting
# one. publish.yml and build-liboqs.yml never run outside a release, so without
# this a typo in either surfaces mid-release.
check-action-pins:
	@$(FVM) dart scripts/check_action_pins.dart $(ARGS)

# actionlint — static checks over .github/workflows: YAML schema, ${{ }}
# expression types, runner labels, action and reusable-workflow input contracts,
# and shellcheck over every `run:` block. Pinned by version AND SHA256, because
# GitHub release assets are mutable and the checksum is the real lock (same rule
# as .github/actions/setup-make). Dependabot cannot see this pin — see
# CONTRIBUTING.md, "Pins Dependabot Cannot See".
ACTIONLINT_VERSION ?= 1.7.12
ACTIONLINT_OS   := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ACTIONLINT_ARCH := $(shell uname -m | sed -e 's/^x86_64$$/amd64/' -e 's/^aarch64$$/arm64/')
ACTIONLINT_BIN  := build/tools/actionlint-$(ACTIONLINT_VERSION)

ACTIONLINT_SHA256_darwin_arm64 := aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f
ACTIONLINT_SHA256_darwin_amd64 := 5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644
ACTIONLINT_SHA256_linux_amd64  := 8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
ACTIONLINT_SHA256_linux_arm64  := 325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6
ACTIONLINT_SHA256 := $(ACTIONLINT_SHA256_$(ACTIONLINT_OS)_$(ACTIONLINT_ARCH))

# Hard-fails without shellcheck rather than running: actionlint skips every
# `run:` block when shellcheck is absent and still exits 0, so a green local run
# would prove nothing and CI — where shellcheck is installed — would disagree.
lint-workflows: $(ACTIONLINT_BIN)
	@command -v shellcheck >/dev/null 2>&1 || { \
	  echo "ERROR: shellcheck not found. actionlint silently SKIPS every run: block"; \
	  echo "       without it and still exits 0, so this would prove nothing."; \
	  echo "       Install it (brew install shellcheck); CI runners already have it."; \
	  exit 1; }
	@$(ACTIONLINT_BIN) $(ARGS)

$(ACTIONLINT_BIN):
ifeq ($(ACTIONLINT_SHA256),)
	@echo "ERROR: no pinned actionlint checksum for $(ACTIONLINT_OS)/$(ACTIONLINT_ARCH)."
	@echo "       Add one to the Makefile, or run this check on Linux or macOS."
	@exit 1
else
	@mkdir -p $(dir $@)
	@set -eu; \
	tmp="$$(mktemp -d)"; trap 'rm -rf "$$tmp"' EXIT; \
	url="https://github.com/rhysd/actionlint/releases/download/v$(ACTIONLINT_VERSION)/actionlint_$(ACTIONLINT_VERSION)_$(ACTIONLINT_OS)_$(ACTIONLINT_ARCH).tar.gz"; \
	echo "Downloading $$url"; \
	curl -fsSL --retry 3 --retry-delay 5 -o "$$tmp/actionlint.tar.gz" "$$url"; \
	if command -v sha256sum >/dev/null 2>&1; then \
	  actual="$$(sha256sum "$$tmp/actionlint.tar.gz" | cut -d' ' -f1)"; \
	else \
	  actual="$$(shasum -a 256 "$$tmp/actionlint.tar.gz" | cut -d' ' -f1)"; \
	fi; \
	if [ "$$actual" != "$(ACTIONLINT_SHA256)" ]; then \
	  echo "ERROR: SHA256 mismatch for actionlint $(ACTIONLINT_VERSION) ($(ACTIONLINT_OS)/$(ACTIONLINT_ARCH)):"; \
	  echo "  expected $(ACTIONLINT_SHA256)"; \
	  echo "  actual   $$actual"; \
	  exit 1; \
	fi; \
	tar -xzf "$$tmp/actionlint.tar.gz" -C "$$tmp" actionlint; \
	mv "$$tmp/actionlint" "$@"; \
	chmod +x "$@"; \
	echo "actionlint $(ACTIONLINT_VERSION) -> $@"
endif

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
