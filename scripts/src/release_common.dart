// Shared helpers for the release script (`release.dart`).
//
// These wrap git and terminal interaction. `runInherit` starts subprocesses
// with `ProcessStartMode.inheritStdio` so interactive prompts — notably the
// commit/tag signing — work during a release.
library;

import 'dart:io';

import 'common.dart';

/// Ensures the current directory is inside a git work tree.
Future<void> ensureGitRepo() async {
  final result = await Process.run('git', [
    'rev-parse',
    '--is-inside-work-tree',
  ]);
  if (result.exitCode != 0 || (result.stdout as String).trim() != 'true') {
    throw Exception('Not inside a git repository.');
  }
}

/// Runs a read-only git command and returns trimmed stdout, throwing on error.
Future<String> git(List<String> args) async {
  final result = await Process.run('git', args);
  if (result.exitCode != 0) {
    throw Exception(
      'git ${args.join(' ')} failed: ${(result.stderr as String).trim()}',
    );
  }
  return (result.stdout as String).trim();
}

/// Runs a command with inherited stdio (so interactive prompts — e.g. a
/// signing passphrase — work), throwing on a non-zero exit.
///
/// Always fails loud: a non-zero exit throws even when [failMessage] is null
/// (with a generic message), so a failed step — e.g. `git add` hitting a stale
/// `.git/index.lock` — cannot silently fall through into the next command.
Future<void> runInherit(
  String command,
  List<String> args, {
  String? failMessage,
}) async {
  final process = await Process.start(
    command,
    args,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    final message = failMessage ?? '`$command ${args.join(' ')}` failed';
    throw Exception('$message (exit $code)');
  }
}

/// Prompts a yes/no question on the terminal; defaults to no.
bool confirm(String prompt) {
  stdout.write('$prompt [y/N] ');
  final answer = (stdin.readLineSync() ?? '').trim().toLowerCase();
  return answer == 'y' || answer == 'yes';
}

/// Whether the native release for a given full version exists.
enum NativeReleaseStatus { exists, missing, inconclusive }

/// Outcome of a native-release existence check.
class NativeCheck {
  NativeCheck(this.status, [this.detail = '']);
  final NativeReleaseStatus status;
  final String detail;
}

/// Checks whether the GitHub Release `liboqs-<fullVersion>` exists, using the
/// `gh` CLI (which auto-resolves the repo from the git remote).
///
/// Distinguishes a definite "missing" (gh reports "release not found") from an
/// "inconclusive" result (gh absent, not authenticated, or a network/API
/// error) so the caller can fail closed on both while giving a useful message.
Future<NativeCheck> checkNativeRelease(String fullVersion) async {
  final tag = 'liboqs-$fullVersion';

  if (!await commandExists('gh')) {
    return NativeCheck(
      NativeReleaseStatus.inconclusive,
      'the `gh` CLI is not installed',
    );
  }

  final result = await Process.run('gh', [
    'release',
    'view',
    tag,
    '--json',
    'tagName',
  ]);
  if (result.exitCode == 0) {
    return NativeCheck(NativeReleaseStatus.exists);
  }

  final stderr = (result.stderr as String).trim();
  if (stderr.toLowerCase().contains('release not found')) {
    return NativeCheck(NativeReleaseStatus.missing);
  }
  return NativeCheck(
    NativeReleaseStatus.inconclusive,
    stderr.isEmpty ? 'gh release view exited ${result.exitCode}' : stderr,
  );
}

/// Returns true if [a] is a strictly greater X.Y.Z version than [b].
///
/// If either side can't be parsed as X.Y.Z, logs a warning and returns true so
/// a release is not blocked on a parse quirk.
bool isNewerVersion(String a, String b) {
  List<int>? parse(String v) {
    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(v.trim());
    if (m == null) return null;
    return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
  }

  final pa = parse(a);
  final pb = parse(b);
  if (pa == null || pb == null) {
    logWarn(
      'Could not compare versions "$a" and "$b"; skipping the '
      'greater-than check.',
    );
    return true;
  }
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] > pb[i];
  }
  return false;
}
