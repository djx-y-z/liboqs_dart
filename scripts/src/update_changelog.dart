// Update CHANGELOG.md with AI-generated entry for a liboqs dependency update.
//
// Uses GitHub Models API (OpenAI-compatible) to analyze the upstream release
// notes and commit list and generate a changelog entry that matches this
// project's house style.
//
// NOTE: This step does NOT bump the Dart package version. The package version
// is bumped as a deliberate release step (`make release`), which also
// finalizes the `[Unreleased]` section. The automatic update PR only records
// the liboqs dependency change (liboqs Highlight + Changed entry).
library;

import 'dart:convert';
import 'dart:io';

import 'common.dart';

/// Update CHANGELOG.md with a new liboqs version entry.
Future<void> updateChangelog({
  required String version,
  required String token,
  String? fromVersion,
  bool ciMode = false,
}) async {
  final packageDir = getPackageDir();

  // Step 1: Fetch release notes from GitHub.
  logStep('Fetching release notes for $version...');
  final releaseNotes = await _fetchReleaseNotes(version);
  logInfo('Got ${releaseNotes.length} characters of release notes');

  // Step 2: Fetch the actual commit list between the two tags — release notes
  // alone are often terse, which produces incomplete changelog entries.
  var upstreamCommits = '';
  if (fromVersion != null && fromVersion != version) {
    logStep('Fetching upstream commits $fromVersion...$version...');
    try {
      upstreamCommits = await _fetchUpstreamCommits(fromVersion, version);
      logInfo('Got ${upstreamCommits.length} characters of commit history');
    } catch (e) {
      logWarning('Could not fetch upstream commit list: $e');
    }
  }

  // Step 3: Read current CHANGELOG.
  logStep('Reading CHANGELOG.md...');
  final changelogFile = File('${packageDir.path}/CHANGELOG.md');
  final currentChangelog = changelogFile.readAsStringSync();

  // Step 4: Analyze with AI.
  logStep('Analyzing with GitHub Models AI...');
  final aiResponse = await _generateChangelogEntry(
    version: version,
    fromVersion: fromVersion,
    releaseNotes: releaseNotes,
    upstreamCommits: upstreamCommits,
    currentChangelog: currentChangelog,
    token: token,
  );

  // Parse AI response.
  final parsed = jsonDecode(aiResponse) as Map<String, dynamic>;
  final nativeHighlight = parsed['liboqs_highlight'] as String;
  final changed = parsed['changed'] as String;
  logInfo('Generated liboqs highlight: $nativeHighlight');
  logInfo('Generated changed entry');

  // Step 5: Update CHANGELOG.
  logStep('Updating CHANGELOG.md...');
  final updatedChangelog = insertChangelogEntry(
    currentChangelog: currentChangelog,
    nativeHighlight: nativeHighlight,
    changed: changed,
  );

  await changelogFile.writeAsString(updatedChangelog);
  logInfo('CHANGELOG.md updated');
}

/// Fetch release notes from the GitHub API.
///
/// liboqs release tags are plain version numbers (e.g. `0.16.0`, no `v`
/// prefix).
Future<String> _fetchReleaseNotes(String version) async {
  final result = await Process.run('curl', [
    '-s',
    'https://api.github.com/repos/open-quantum-safe/liboqs/releases/tags/$version',
  ]);

  if (result.exitCode != 0) {
    throw Exception('Failed to fetch release from GitHub');
  }

  final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;

  if (json.containsKey('message') && json['message'] == 'Not Found') {
    throw Exception('Release $version not found');
  }

  return json['body'] as String? ?? 'No release notes available.';
}

/// Fetch the commit list between two upstream tags via the GitHub compare API.
///
/// Returns a newline-separated list of first-line commit messages (merge
/// commits excluded), capped to keep the AI prompt within limits.
Future<String> _fetchUpstreamCommits(String from, String to) async {
  final result = await Process.run('curl', [
    '-s',
    'https://api.github.com/repos/open-quantum-safe/liboqs/compare/$from...$to?per_page=250',
  ]);

  if (result.exitCode != 0) {
    throw Exception('Failed to fetch compare from GitHub');
  }

  final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  if (json['commits'] == null) {
    throw Exception(json['message'] ?? 'No commits in compare response');
  }

  final commits = json['commits'] as List<Object?>;
  final totalCommits = json['total_commits'] as int? ?? commits.length;
  final messages = <String>[];
  for (final commit in commits) {
    final message =
        (((commit as Map<String, dynamic>)['commit']
                    as Map<String, dynamic>)['message']
                as String)
            .split('\n')
            .first
            .trim();
    if (message.startsWith('Merge ')) continue;
    messages.add('- $message');
  }

  const maxChars = 8000;
  var listing = messages.join('\n');
  if (listing.length > maxChars) {
    listing = '${listing.substring(0, maxChars)}\n- ... (truncated)';
  }
  if (totalCommits > commits.length) {
    listing += '\n- ... and ${totalCommits - commits.length} more commits';
  }
  return listing;
}

/// Generate changelog entry using the GitHub Models API.
Future<String> _generateChangelogEntry({
  required String version,
  required String? fromVersion,
  required String releaseNotes,
  required String upstreamCommits,
  required String currentChangelog,
  required String token,
}) async {
  // Extract recent changelog entries for context (first 150 lines).
  final changelogContext = currentChangelog.split('\n').take(150).join('\n');

  // Prefer a compare link (the release notes are often incomplete); fall back
  // to the release-notes link when the previous version is unknown.
  final sourceLink = fromVersion != null && fromVersion != version
      ? '[compare](https://github.com/open-quantum-safe/liboqs/compare/$fromVersion...$version)'
      : '[release notes](https://github.com/open-quantum-safe/liboqs/releases/tag/$version)';

  final prompt =
      '''
You are updating CHANGELOG.md for **liboqs_dart** (pub.dev package `liboqs`),
a Dart FFI wrapper around the liboqs C library. It just updated its bundled
liboqs native library to $version.

## What this library actually exposes (CRITICAL for classification)
The wrapper binds liboqs' GENERIC APIs and exposes them 1:1:
- `OQS_KEM` (key encapsulation): every algorithm that liboqs enables by
  default is reachable by name via `KEM.create('<name>')`.
- `OQS_SIG` (signatures): same, via `Signature.create('<name>')`.
- `OQS_randombytes` (secure random) and the `OQS_MEM_*` memory helpers.

Because algorithms are addressed BY NAME through the generic API, the
following upstream changes ARE user-visible and deserve their own bullets:
- algorithms added, removed, renamed, or switched between enabled/disabled by
  default (this changes what `create()` accepts — removals/renames are
  **BREAKING:**)
- changes to an algorithm's wire format, keys, ciphertexts, or signatures
  (interoperability breaks even when the name stays the same — treat as
  **BREAKING:** and say so explicitly)
- security fixes in algorithm implementations or the common code (call these
  out clearly, users must know to upgrade)
- changes to the generic `OQS_KEM`/`OQS_SIG`/`OQS_randombytes` API surface

Treat these as INVISIBLE to this package's users (never present them as a
feature/change of this package): CI and test-harness changes, documentation,
formal-verification tooling, language wrappers shipped by upstream, build
system refactors that do not change the shipped algorithm set, and platforms
this package does not ship (it ships Linux x86_64, macOS, Windows x86_64, iOS,
Android).

## liboqs release notes for $version:
$releaseNotes
${upstreamCommits.isEmpty ? '' : '''

## Upstream commits included in this update (first lines):
$upstreamCommits

Use BOTH the release notes and the commit list — release notes are often
incomplete, and the commit list shows what actually changed.'''}

## Current CHANGELOG.md (match this house style exactly):
$changelogContext

## Your task
Return a JSON object with EXACTLY two string fields:
1. "liboqs_highlight" — a single Highlights line for the liboqs update.
2. "changed" — the "#### Changed" entry.

## Rules for "liboqs_highlight"
1. Format exactly: "**liboqs $version** — <brief 3-10 word description>".
2. Mention breaking algorithm changes or security fixes if there are any;
   otherwise use a brief neutral summary like "maintenance update".

## Rules for "changed" (THIS IS THE IMPORTANT PART — match the house style)
1. First line exactly: "- Update bundled liboqs native library to $version ($sourceLink)".
2. Classify EVERY upstream change using the visibility rules above:
   - User-visible changes each get their own indented sub-bullet. Prefix
     breaking ones with "**BREAKING:**" and name the exact algorithm
     identifiers affected (users match on these strings).
   - Invisible changes get at most ONE collective sub-bullet ending with
     "— none of which affects this package's API or shipped libraries".
3. Mention security fixes explicitly with upstream PR/issue links when the
   release notes provide them.
4. If nothing user-visible changed, say so explicitly, e.g. "No changes to the
   exposed KEM/signature algorithm set or the generic API".
5. Judge relevance from the release notes AND the commit list, NOT from the
   version numbers.

## Example output (house style — follow this SHAPE):
```json
{
  "liboqs_highlight": "**liboqs 0.17.0** — maintenance update, no algorithm changes",
  "changed": "- Update bundled liboqs native library to 0.17.0 ([compare](https://github.com/open-quantum-safe/liboqs/compare/0.16.0...0.17.0))\\n  - Upstream changes are limited to CI, documentation, and build-system cleanups — none of which affects this package's API or shipped libraries\\n  - No changes to the exposed KEM/signature algorithm set or the generic API"
}
```

Return ONLY valid JSON, no markdown code blocks.
''';

  final requestBody = jsonEncode({
    'model': 'gpt-4o-mini',
    'messages': [
      {'role': 'user', 'content': prompt},
    ],
    'temperature': 0.3,
    'max_tokens': 800,
  });

  final result = await Process.run('curl', [
    '-s',
    '-X',
    'POST',
    'https://models.github.ai/inference/chat/completions',
    '-H',
    'Content-Type: application/json',
    '-H',
    'Authorization: Bearer $token',
    '-d',
    requestBody,
  ]);

  if (result.exitCode != 0) {
    throw Exception('GitHub Models API request failed');
  }

  final response = jsonDecode(result.stdout as String) as Map<String, dynamic>;

  if (response.containsKey('error')) {
    final error = response['error'] as Map<String, dynamic>;
    throw Exception('API error: ${error['message']}');
  }

  final choices = response['choices'] as List<Object?>?;
  if (choices == null || choices.isEmpty) {
    throw Exception('No response from AI');
  }

  final firstChoice = choices[0];
  if (firstChoice is! Map<String, dynamic>) {
    throw Exception('Invalid response format from AI');
  }
  final message = firstChoice['message'] as Map<String, dynamic>?;
  if (message == null) {
    throw Exception('No message in AI response');
  }
  final content = (message['content'] as String).trim();

  // Parse JSON response.
  try {
    final parsed = jsonDecode(content) as Map<String, dynamic>;
    return jsonEncode(parsed); // Return normalized JSON.
  } catch (e) {
    // If AI didn't return valid JSON, try to extract it.
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
    if (jsonMatch != null) {
      return jsonMatch.group(0)!;
    }
    // Fallback: minimal entry from the raw content.
    return jsonEncode({
      'liboqs_highlight': '**liboqs $version** — dependency update',
      'changed': content,
    });
  }
}

/// Insert the new changelog entry in the correct location. Pure; exposed for
/// testing.
///
/// Strategy:
/// 1. If an [Unreleased] section exists, add the entry to its For Users
///    Highlights and Changed subsections.
/// 2. If no [Unreleased] section exists (this project's convention between
///    releases), create one before the first version section.
String insertChangelogEntry({
  required String currentChangelog,
  required String nativeHighlight,
  required String changed,
}) {
  final lines = currentChangelog.split('\n');

  final hasUnreleased = lines.any((l) => l.startsWith('## [Unreleased]'));

  if (hasUnreleased) {
    return _insertIntoUnreleased(lines, nativeHighlight, changed);
  } else {
    return _createUnreleasedSection(lines, nativeHighlight, changed);
  }
}

/// Insert entry into an existing [Unreleased] section.
String _insertIntoUnreleased(
  List<String> lines,
  String nativeHighlight,
  String changed,
) {
  final result = <String>[];
  var inUnreleased = false;
  var inForUsers = false;
  var insertedHighlights = false;
  var insertedChanged = false;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];

    // Check for ## [Unreleased] section.
    if (line.startsWith('## [Unreleased]')) {
      inUnreleased = true;
      result.add(line);
      continue;
    }

    // Check for next version section (end of Unreleased).
    if (inUnreleased &&
        line.startsWith('## [') &&
        !line.contains('Unreleased')) {
      // If we haven't inserted yet, create the structure.
      if (!insertedHighlights || !insertedChanged) {
        result.addAll([
          '',
          '### For Users',
          '',
          '#### ✨ Highlights',
          '',
          '- $nativeHighlight',
          '',
          '#### Changed',
          '',
          changed,
          '',
        ]);
        insertedHighlights = true;
        insertedChanged = true;
      }
      inUnreleased = false;
      inForUsers = false;
      result.add(line);
      continue;
    }

    // Check for ### For Users in Unreleased.
    if (inUnreleased && line.startsWith('### For Users')) {
      inForUsers = true;
      result.add(line);
      continue;
    }

    // Check for next ### section (end of For Users).
    if (inForUsers && line.startsWith('### ') && !line.contains('For Users')) {
      // If we haven't inserted yet, insert before this section.
      if (!insertedHighlights || !insertedChanged) {
        result.addAll([
          '',
          '#### ✨ Highlights',
          '',
          '- $nativeHighlight',
          '',
          '#### Changed',
          '',
          changed,
          '',
        ]);
        insertedHighlights = true;
        insertedChanged = true;
      }
      inForUsers = false;
      result.add(line);
      continue;
    }

    // Check for #### ✨ Highlights in For Users.
    if (inForUsers && line.contains('Highlights')) {
      result.add(line);
      result.add('');
      result.add('- $nativeHighlight');
      insertedHighlights = true;
      // Skip the next empty line if present.
      if (i + 1 < lines.length && lines[i + 1].trim().isEmpty) {
        i++;
      }
      continue;
    }

    // Check for #### Changed in For Users.
    if (inForUsers && line.startsWith('#### Changed')) {
      // If Highlights wasn't found, add it before Changed.
      if (!insertedHighlights) {
        result.addAll(['', '#### ✨ Highlights', '', '- $nativeHighlight', '']);
        insertedHighlights = true;
      }
      result.addAll([line, '', changed]);
      insertedChanged = true;
      // Skip the next empty line if present.
      if (i + 1 < lines.length && lines[i + 1].trim().isEmpty) {
        i++;
      }
      continue;
    }

    result.add(line);
  }

  return result.join('\n');
}

/// Create a new [Unreleased] section at the top.
String _createUnreleasedSection(
  List<String> lines,
  String nativeHighlight,
  String changed,
) {
  final result = <String>[];

  // Find the first version line (## [X.Y.Z]).
  var insertIndex = 0;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('## [') && !lines[i].contains('Unreleased')) {
      insertIndex = i;
      break;
    }
  }

  // Add lines before first version, Unreleased section, and remaining lines.
  result
    ..addAll(lines.sublist(0, insertIndex))
    ..addAll([
      '## [Unreleased]',
      '',
      '### For Users',
      '',
      '#### ✨ Highlights',
      '',
      '- $nativeHighlight',
      '',
      '#### Changed',
      '',
      changed,
      '',
    ])
    ..addAll(lines.sublist(insertIndex));

  return result.join('\n');
}
