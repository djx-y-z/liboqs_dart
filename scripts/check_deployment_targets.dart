#!/usr/bin/env dart

/// Check Apple deployment target consistency across the native build scripts.
///
/// The expected versions below are the single source of truth. The script
/// verifies every location where a deployment target is declared in the iOS and
/// macOS build scripts and fails if any of them drift. (This is a plain Dart FFI
/// package — it ships no podspecs — so the build scripts are the only place
/// these targets live; the guard mainly keeps the four macOS locations, across
/// the universal and single-arch branches, internally consistent.)
///
/// Note: the macOS x86_64 floor is 10.15 (lowest supported Intel macOS) while
/// the arm64 slice is built with an 11.0 floor (first Apple-silicon macOS),
/// which is intentionally higher; the shipped dylib is universal.
///
/// Usage:
///   make check-targets                # verify
///   make check-targets ARGS="--update"  # rewrite mismatches in-place
///
/// Exit codes:
///   0 - All files match
///   1 - Mismatch found (use --update to fix)
///   2 - Error occurred (file or declaration not found)
library;

import 'dart:io';

import 'src/common.dart';

// ============================================
// Source of truth
// ============================================

/// Minimum iOS version (device and simulator).
const iosMinVersion = '13.0';

/// Minimum macOS version for the x86_64 slice (and the universal dylib).
const macosX64MinVersion = '10.15';

/// Minimum macOS version for the arm64 slice (first Apple-silicon macOS).
const macosArm64MinVersion = '11.0';

// ============================================
// Checked locations
// ============================================

class _Check {
  final String file;
  final String description;

  /// Pattern with exactly one capture group: the version string.
  final RegExp pattern;
  final String expected;

  _Check(this.file, this.description, String pattern, this.expected)
    : pattern = RegExp(pattern);
}

final _checks = <_Check>[
  _Check(
    'scripts/src/build_ios.dart',
    'iOS cmake deployment target',
    r'-DCMAKE_OSX_DEPLOYMENT_TARGET=([\d.]+)',
    iosMinVersion,
  ),
  _Check(
    'scripts/src/build_macos.dart',
    'macOS arm64 deployment target (universal branch)',
    r"arch:\s*'arm64',\s*deploymentTarget:\s*'([\d.]+)'",
    macosArm64MinVersion,
  ),
  _Check(
    'scripts/src/build_macos.dart',
    'macOS x86_64 deployment target (universal branch)',
    r"arch:\s*'x86_64',\s*deploymentTarget:\s*'([\d.]+)'",
    macosX64MinVersion,
  ),
  _Check(
    'scripts/src/build_macos.dart',
    'macOS arm64 deployment target (single-arch branch)',
    r"MacOSArch\.arm64\s*\?\s*'([\d.]+)'",
    macosArm64MinVersion,
  ),
  _Check(
    'scripts/src/build_macos.dart',
    'macOS x86_64 deployment target (single-arch branch)',
    r"MacOSArch\.arm64\s*\?\s*'[\d.]+'\s*:\s*'([\d.]+)'",
    macosX64MinVersion,
  ),
];

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    print(
      'Usage: make check-targets [ARGS="--update"]\n'
      '\n'
      'Checks that every deployment-target declaration matches the expected\n'
      'versions defined at the top of scripts/check_deployment_targets.dart:\n'
      '  iOS:          $iosMinVersion\n'
      '  macOS x86_64: $macosX64MinVersion (universal floor)\n'
      '  macOS arm64:  $macosArm64MinVersion\n'
      '\n'
      'Options:\n'
      '  --update    Rewrite mismatched declarations in-place\n'
      '  --help, -h  Show this help',
    );
    exit(0);
  }

  final doUpdate = args.contains('--update');
  final packageRoot = getPackageDir().path;

  var mismatches = 0;
  var errors = 0;

  for (final check in _checks) {
    final file = File('$packageRoot/${check.file}');
    if (!file.existsSync()) {
      logError('${check.file}: file not found');
      errors++;
      continue;
    }

    var content = file.readAsStringSync();
    final matches = check.pattern.allMatches(content).toList();

    if (matches.isEmpty) {
      logError(
        '${check.file}: declaration not found (${check.description}) — '
        'the file may have been refactored; update the pattern in '
        'scripts/check_deployment_targets.dart',
      );
      errors++;
      continue;
    }

    final wrong = matches.where((m) => m.group(1) != check.expected).toList();
    if (wrong.isEmpty) {
      logInfo('${check.file}: ${check.description} = ${check.expected} — OK');
      continue;
    }

    final found = wrong.map((m) => m.group(1)).join(', ');
    if (doUpdate) {
      content = content.replaceAllMapped(check.pattern, (m) {
        final full = m.group(0)!;
        return full.replaceFirst(m.group(1)!, check.expected);
      });
      file.writeAsStringSync(content);
      logWarn(
        '${check.file}: ${check.description} was $found — '
        'updated to ${check.expected}',
      );
    } else {
      logError(
        '${check.file}: ${check.description} is $found, '
        'expected ${check.expected}',
      );
      mismatches++;
    }
  }

  if (errors > 0) {
    exit(2);
  }
  if (mismatches > 0) {
    logError(
      'Deployment targets are inconsistent. '
      'Run `make check-targets ARGS="--update"` to fix.',
    );
    exit(1);
  }
  logInfo('All deployment targets are consistent.');
}
