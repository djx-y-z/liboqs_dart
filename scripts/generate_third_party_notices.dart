#!/usr/bin/env dart

/// Generate or verify THIRD_PARTY_NOTICES.txt for the shipped native library.
///
/// The native library is compiled from the liboqs C sources, which vendor code
/// from many upstream projects under licences other than liboqs' own MIT. Those
/// licences require their notices to travel with a binary distribution, and
/// Flutter's `LicenseRegistry` does not cover them — it collects LICENSE files
/// of pub packages, not of C code compiled into a native library.
///
/// The file is committed rather than generated on demand, because it ships in
/// the published package and inside every native release archive. It is
/// deliberately NOT declared as a Flutter asset: a package-declared asset is
/// bundled into every consuming app whether or not it is used. Apps that want
/// to show these notices can copy it into their own assets and register it with
/// `LicenseRegistry.addLicense` (see README).
///
/// Usage:
///   make third-party-notices                  # regenerate and write
///   make third-party-notices ARGS="--refresh" # re-clone the liboqs sources
///   make verify-third-party-notices           # verify, write nothing
///
/// Exit codes:
///   0 - Generated, or (with --check) the committed file is current
///   1 - (--check only) the committed file is missing or out of date
///   2 - Error occurred
library;

import 'dart:io';

import 'src/common.dart';
import 'src/third_party_notices.dart';

void main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    exit(0);
  }

  final check = args.contains('--check');
  final refresh = args.contains('--refresh');

  try {
    final generated = await generateNotices(refresh: refresh);
    final target = noticesPath();

    if (check) {
      final drift = describeDrift(generated: generated, path: target);
      if (drift != null) {
        logError(drift);
        exit(1);
      }
      logSuccess('THIRD_PARTY_NOTICES.txt is up to date');
      return;
    }

    File(target).writeAsStringSync(generated);
    final sizeKb = (generated.length / 1024).toStringAsFixed(1);
    logSuccess('Wrote $target ($sizeKb KB)');
  } catch (e) {
    logError('$e');
    exit(2);
  }
}

void _printUsage() {
  // ignore: avoid_print
  print(
    'Generate or verify THIRD_PARTY_NOTICES.txt\n'
    '\n'
    'Usage:\n'
    '  make third-party-notices                  Regenerate and write\n'
    '  make third-party-notices ARGS="--refresh" Re-clone the liboqs sources\n'
    '  make verify-third-party-notices           Verify, write nothing\n'
    '\n'
    'Options:\n'
    '  --check      Verify the committed file is up to date (no writes)\n'
    '  --refresh    Discard the cached liboqs checkout and clone again\n'
    '  --help, -h   Show this help\n'
    '\n'
    'The liboqs version is read from liboqs.native_version in pubspec.yaml.',
  );
}
