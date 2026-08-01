/// Build the third-party licence inventory for the native library this package
/// ships.
///
/// The shipped `liboqs.so`/`.dylib`/`.dll` is compiled from the liboqs source
/// tree, which vendors code from many upstream projects under licences other
/// than liboqs' own MIT. `LICENSE.txt` at the root of liboqs says so itself:
///
/// > liboqs includes some third party libraries or modules that are licensed
/// > differently; the corresponding subfolder contains the license that applies
/// > in that case.
///
/// Those licences require their notices to travel with a binary distribution,
/// and Flutter's `LicenseRegistry` does not help — it collects LICENSE files of
/// pub packages, not of C code compiled into a native library.
///
/// ## Why the whole tree rather than the compiled file list
///
/// The obvious approach is to configure CMake and read the real link line, so
/// that only algorithms actually built get attributed. That was measured
/// against liboqs 0.16.0 across all eleven artifacts this package ships (Linux
/// x86_64/arm64, macOS arm64/x86_64, Windows x86_64, Android arm64-v8a /
/// armeabi-v7a / x86_64, iOS device-arm64 and simulator arm64/x86_64), and the
/// union of their link lines implicates 151 of the tree's 153 licence files.
/// The two it leaves out are `src/sig_stfl/xmss/LICENSE` and
/// `src/sig_stfl/lms/external/license.txt` — the stateful signature schemes,
/// which `OQS_ENABLE_SIG_STFL` leaves off and this package never turns on.
///
/// So "union over every artifact we ship" and "the tree minus `src/sig_stfl/`"
/// are the same set, and the second needs no toolchain. That matters for more
/// than convenience: a CMake-driven inventory depends on the host that ran it
/// (iOS needs Xcode, Android needs the NDK, and `OQS_DIST_BUILD` changes which
/// optimised variant directories compile), so the byte-exact check below could
/// never pass on a runner other than the one that generated the file.
///
/// ## Why licences are resolved from four places, not one
///
/// Walking up to the nearest LICENSE file — the obvious implementation — is
/// wrong for 43% of what this generator reads: 2532 of the 5957 sources under
/// `src/` have no licence file anywhere between them and the repository root,
/// so the walk files them under liboqs' MIT. (Measured over the same set the
/// generator walks — sources and headers alike. Counting only the `.c`/`.S`
/// files one artifact actually compiles gives 1167 of 2596, the same picture.) Measured examples: the 435 UOV sources declare
/// `CC0 OR Apache-2.0`, `src/common/common.c` declares `Apache-2.0 AND MIT`
/// (a conjunction — Apache-2.0's obligations apply unconditionally to every
/// binary this package ships), FrodoKEM and HQC state their licence only in
/// `docs/algorithms/`, and the XKCP Keccak sources carry a CC0 waiver in prose
/// with no tag at all.
///
/// Each source is therefore resolved through, in order:
///   A. an `SPDX-License-Identifier:` tag in the file itself,
///   B. the nearest LICENSE/NOTICE file at or below `src/`,
///   C. `spdx-license-identifier` in `docs/algorithms/<class>/<family>.yml`,
///   D. an explicit override, for in-tree code covered by none of the above.
///
/// A source matched by none of the four is a hard error rather than a silent
/// MIT attribution — that is what keeps this honest across liboqs upgrades.
library;

import 'dart:convert';
import 'dart:io';

import 'common.dart';

// ============================================
// Scope of the inventory
// ============================================

/// File extensions treated as source of the shipped library.
///
/// Headers count: they carry licence notices of their own — BIKE's
/// `functions_renaming.h` holds a full BSD-3-Clause notice inside an otherwise
/// Apache-2.0 tree — and their contents are compiled into the binary just the
/// same.
const _sourceExtensions = {'.c', '.h', '.S', '.s', '.inc'};

/// Subtrees left out of the inventory, with the reason each is absent from the
/// shipped binary. Both were verified against a configured build tree rather
/// than assumed — see the library doc comment.
const _excludedPaths = <String, String>{
  'src/sig_stfl':
      'stateful signatures (XMSS, LMS); OQS_ENABLE_SIG_STFL is off by default '
      'and this package never enables it',
  'src/common/rand/rand_nist.c':
      'compiled only into the `internal` object library that liboqs exposes to '
      'its test programs (src/common/CMakeLists.txt), never linked into '
      'the shared library this package ships',
};

/// Licence identifiers this generator understands.
///
/// An unknown identifier is a hard error, not a fallback: a liboqs release that
/// vendors code under a new licence has to be looked at by a person, and
/// failing here is the only thing that forces that.
const _knownLicenceIds = {
  'Apache-2.0',
  'BSD-3-Clause',
  'CC0',
  'CC0-1.0',
  'ISC',
  'MIT',
};

/// Declarations that are not SPDX expressions but state a licence plainly.
const _knownBareDeclarations = {'Public domain'};

/// Upstream typos in `SPDX-License-Identifier:` lines, normalised on read.
///
/// `Apache-2.0"` is a stray quote in the 41 Amazon-authored files under
/// `src/kem/bike/additional_r4/`, whose own LICENSE is Apache-2.0 — so the
/// fixup only avoids discarding a declaration that is not in doubt.
const _declarationFixups = <String, String>{'Apache-2.0"': 'Apache-2.0'};

/// Licences for in-tree code that declares none of A, B or C.
///
/// Keyed by repository-relative path prefix. Every entry cites what it rests
/// on, because by definition nothing in the tree states it outright.
/// The longest matching prefix wins, so a single file can be carved out of the
/// subtree around it.
const _licenceOverrides = <String, _Override>{
  'src/common/sha3/xkcp_low': _Override(
    'CC0-1.0',
    'the eXtended Keccak Code Package headers state that "the implementer has '
        'waived all copyright and related or neighboring rights to the source '
        'code in this file" and link creativecommons.org/publicdomain/zero/1.0/',
  ),
  // Carved out of the CC0 waiver above: this one file is Andy Polyakov's
  // CRYPTOGAMS assembly, and it says so itself rather than inheriting XKCP's
  // waiver. The licence has no SPDX identifier, hence the LicenseRef- form.
  // liboqs ships no copy of its text, so the notice reproduces the file's own
  // statement and the URL it points at.
  'src/common/sha3/xkcp_low/KeccakP-1600/avx2/KeccakP-1600-AVX2.S': _Override(
    'LicenseRef-CRYPTOGAMS',
    'the file states "The source code in this file is licensed under the '
        'CRYPTOGAMS license. For further details see '
        'http://www.openssl.org/~appro/cryptogams/."',
  ),
};

class _Override {
  final String expression;
  final String evidence;

  const _Override(this.expression, this.evidence);
}

// ============================================
// Model
// ============================================

/// How one source file's licence was established.
class LicenceResolution {
  /// The declared licence expression, verbatim from upstream.
  final String expression;

  /// Where the declaration came from, for the `Declared in:` line.
  ///
  /// Deliberately free of directory paths: liboqs ships the same licence file
  /// once per implementation variant (36 byte-identical MIT files under
  /// `src/sig/snova/` alone), and naming the directory here would split every
  /// one of those into its own entry.
  final String provenance;

  /// Licence texts covering this source, read from LICENSE/NOTICE files and
  /// trimmed; empty when upstream ships none for it.
  final List<String> texts;

  /// Licence terms stated in the source header itself, for code that has no
  /// licence file. Aggregated per component rather than keyed on, because these
  /// differ file by file while stating the same grant.
  final List<String> notices;

  /// What the texts were read from (`LICENSE`, `NOTICE`, `source header`).
  final List<String> textOrigins;

  /// Copyright lines carried by the source headers.
  ///
  /// MIT, BSD and Apache-2.0 all require the copyright notice to be reproduced,
  /// and for the 45% of sources with no licence file of their own the header is
  /// the only place it appears.
  final List<String> copyrights;

  const LicenceResolution({
    required this.expression,
    required this.provenance,
    required this.texts,
    this.notices = const [],
    this.textOrigins = const [],
    this.copyrights = const [],
  });

  /// Identity used to collapse adjacent sources into one entry.
  ///
  /// Keyed on the licence *contents* rather than on where they were found, so
  /// sibling implementation directories under one licence collapse into a
  /// single entry instead of several hundred. Provenance is deliberately absent
  /// — within one component some files carry an SPDX tag and some do not, and
  /// that is a difference in how the same licence was stated, not a different
  /// licence. It is reported per component instead.
  String get key => [expression, ...texts].join(' ');
}

/// One entry in the rendered document.
class NoticeComponent {
  /// What this entry covers: a directory (with a trailing `/`) when its whole
  /// subtree resolves identically, otherwise the individual files.
  final List<String> paths;

  final LicenceResolution resolution;

  /// Every distinct way the licence was established across this component.
  final List<String> provenances;

  /// Every distinct copyright line carried by this component's sources.
  final List<String> copyrights;

  /// Every distinct set of licence terms stated in this component's source
  /// headers, for code liboqs ships no licence file for.
  final List<String> notices;

  /// Upstream project URL, when `docs/algorithms/` records one.
  final String? upstream;

  const NoticeComponent({
    required this.paths,
    required this.resolution,
    required this.provenances,
    required this.copyrights,
    required this.notices,
    this.upstream,
  });
}

/// A resolved inventory, ready to render.
class NoticeInventory {
  final String liboqsVersion;
  final List<NoticeComponent> components;

  const NoticeInventory({
    required this.liboqsVersion,
    required this.components,
  });
}

// ============================================
// Reading the source tree
// ============================================

/// Repository-relative, `/`-separated path of [path] under [root].
String relativePath(String root, String path) {
  var rel = path.substring(root.length);
  rel = rel.replaceAll(r'\', '/');
  while (rel.startsWith('/')) {
    rel = rel.substring(1);
  }
  return rel;
}

bool _isExcluded(String rel) {
  for (final prefix in _excludedPaths.keys) {
    if (rel == prefix || rel.startsWith('$prefix/')) return true;
  }
  return false;
}

/// Every source file under `src/` that ends up in the shipped library.
List<String> collectSources(String root) {
  final srcDir = Directory('$root/src');
  if (!srcDir.existsSync()) {
    throw StateError('No src/ directory in $root — is this a liboqs checkout?');
  }

  final sources = <String>[];
  for (final entity in srcDir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final rel = relativePath(root, entity.path);
    if (_isExcluded(rel)) continue;
    final dot = rel.lastIndexOf('.');
    if (dot < 0) continue;
    if (!_sourceExtensions.contains(rel.substring(dot))) continue;
    sources.add(rel);
  }
  sources.sort();
  return sources;
}

/// Filenames that hold a licence text.
final _licenceFilePattern = RegExp(
  r'^(LICENSE|LICENCE|COPYING|NOTICE|UNLICENSE)',
  caseSensitive: false,
);

/// Directories under `src/` holding licence texts, mapped to those files
/// (repository-relative, sorted).
///
/// The repository root is not included on purpose. Its `LICENSE.txt` covers
/// liboqs' own code, and treating it as the fallback for every orphan source is
/// exactly the misattribution this generator exists to avoid.
Map<String, List<String>> collectLicenceFiles(String root) {
  final result = <String, List<String>>{};

  void scan(Directory dir) {
    final files = <String>[];
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is File) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (_licenceFilePattern.hasMatch(name)) {
          files.add(relativePath(root, entity.path));
        }
      }
    }
    if (files.isNotEmpty) {
      files.sort();
      result[relativePath(root, dir.path)] = files;
    }
  }

  final srcDir = Directory('$root/src');
  scan(srcDir);
  for (final entity in srcDir.listSync(recursive: true, followLinks: false)) {
    if (entity is Directory) {
      final rel = relativePath(root, entity.path);
      if (_isExcluded(rel)) continue;
      scan(entity);
    }
  }
  return result;
}

// ============================================
// A — the declaration in the file itself
// ============================================

final _spdxPattern = RegExp(r'SPDX-License-Identifier:[ \t]*(.+)');

/// Whether [declaration] is a licence expression this generator understands.
bool isKnownDeclaration(String declaration) {
  if (_knownBareDeclarations.contains(declaration)) return true;

  final tokens = declaration
      .replaceAll('(', ' ')
      .replaceAll(')', ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty);
  if (tokens.isEmpty) return false;

  for (final token in tokens) {
    final upper = token.toUpperCase();
    if (upper == 'AND' || upper == 'OR' || upper == 'WITH') continue;
    if (!_knownLicenceIds.contains(token)) return false;
  }
  return true;
}

/// The licence [content] declares, or null when it declares nothing.
///
/// Throws when a declaration is present but unreadable. Two upstream files
/// carry a mangled tag — a stray quote, and one spliced into the middle of a
/// BSD notice — and both also carry an intact one, so "declares something
/// unreadable and nothing else" means a licence nobody has reviewed.
String? declaredLicence(String content, {required String path}) {
  final rejected = <String>[];

  for (final match in _spdxPattern.allMatches(content)) {
    var declaration = match.group(1)!.trim();
    // Trailing comment syntax: ` */`, ` -->`, and the like.
    declaration = declaration.replaceFirst(RegExp(r'\s*(\*/|-->)\s*$'), '');
    declaration = _declarationFixups[declaration] ?? declaration;

    if (isKnownDeclaration(declaration)) return declaration;
    rejected.add(declaration);
  }

  if (rejected.isNotEmpty) {
    throw StateError(
      '$path declares a licence this generator does not know: '
      '${rejected.map((r) => '"$r"').join(', ')}.\n'
      'Add the identifier to _knownLicenceIds in '
      'scripts/src/third_party_notices.dart if it is a real new licence, or to '
      '_declarationFixups if it is an upstream typo — but read the file first.',
    );
  }
  return null;
}

/// The leading comment of [content] when it states licence *terms* itself.
///
/// Deliberately narrow. Almost every liboqs source opens with a comment naming
/// a copyright holder, and embedding all of those would bloat the document with
/// twenty near-identical banners while adding nothing a copyright line does not
/// already say. What this looks for is the rarer case where the grant lives in
/// the file and nowhere else: BIKE's `functions_renaming.h` carries a full
/// BSD-3-Clause notice, the XKCP sources carry a CC0 waiver, and neither has a
/// licence file anywhere above it.
String? leadingNotice(String content) {
  final trimmed = content.trimLeft();
  if (!trimmed.startsWith('/*')) return null;
  final end = trimmed.indexOf('*/');
  if (end < 0) return null;

  final block = trimmed.substring(0, end + 2);
  const termsMarkers = [
    'Redistribution and use',
    'Permission is hereby granted',
    'Permission to use',
    'waived all copyright',
    'THE SOFTWARE IS PROVIDED',
  ];
  if (!termsMarkers.any(block.contains)) return null;

  // Strip the comment furniture so the embedded notice reads as prose.
  final lines = block.split('\n').map((line) {
    var stripped = line.trimRight();
    stripped = stripped.replaceFirst(RegExp(r'^\s*/\*+'), '');
    stripped = stripped.replaceFirst(RegExp(r'\s*\*+/\s*$'), '');
    stripped = stripped.replaceFirst(RegExp(r'^\s*\*+ ?'), '');
    return stripped.trimRight();
  }).toList();

  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  if (lines.isEmpty) return null;
  return lines.join('\n');
}

/// Copyright lines declared in the first comment block of [content].
///
/// Kept to the head of the file so that a copyright notice quoted inside, say,
/// an embedded test vector or a reference URL does not become an attribution.
List<String> copyrightLines(String content) {
  final head = content.length > 4000 ? content.substring(0, 4000) : content;
  final found = <String>{};

  for (final raw in const LineSplitter().convert(head)) {
    var line = raw.trim();
    line = line.replaceFirst(RegExp(r'^(//+|/\*+|\*+|#)\s?'), '').trim();
    line = line.replaceFirst(RegExp(r'\s*\*+/\s*$'), '').trim();
    if (!RegExp(r'^Copyright\b', caseSensitive: false).hasMatch(line)) continue;
    // "Copyright:" headings and bare "Copyright (c)" with no holder say nothing.
    if (line.length < 15) continue;
    found.add(line);
  }

  final result = found.toList()..sort();
  return result;
}

// ============================================
// C — docs/algorithms/<class>/<family>.yml
// ============================================

/// What `docs/algorithms/` records for one algorithm family.
class FamilyLicence {
  final String? expression;
  final String? source;

  const FamilyLicence({this.expression, this.source});
}

/// The `primary-upstream:` block: its heading, then every line indented under
/// it.
///
/// Matching the indented lines rather than "everything up to the next
/// top-level key" is what makes this work when the block is the last thing in
/// the file — Dart regexps have no `\z`, so an end-of-input alternative reads
/// as a literal `z` and quietly fails to match.
final _yamlPrimaryUpstream = RegExp(
  r'^primary-upstream:[ \t]*\r?\n((?:[ \t]+[^\n]*\r?\n?)*)',
  multiLine: true,
);
final _yamlSpdx = RegExp(
  r'^\s+spdx-license-identifier:\s*(.+)$',
  multiLine: true,
);
final _yamlSource = RegExp(r'^\s+source:\s*(.+)$', multiLine: true);

/// Licence metadata per `<class>/<family>` (for example `kem/frodokem`).
///
/// Parsed with regexes rather than a YAML package: two scalar fields of one
/// block are all that is needed, and a maintainer script should not add a
/// dependency to the published package.
Map<String, FamilyLicence> collectFamilyLicences(String root) {
  final result = <String, FamilyLicence>{};

  for (final cls in ['kem', 'sig']) {
    final dir = Directory('$root/docs/algorithms/$cls');
    if (!dir.existsSync()) continue;

    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.yml')) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      final family = name.substring(0, name.length - '.yml'.length);

      final content = entity.readAsStringSync();
      final block = _yamlPrimaryUpstream.firstMatch(content)?.group(1) ?? '';
      final spdx = _yamlSpdx.firstMatch(block)?.group(1)?.trim();
      final source = _yamlSource.firstMatch(block)?.group(1)?.trim();

      result['$cls/$family'] = FamilyLicence(
        expression: _nonEmpty(spdx),
        source: _nonEmpty(source),
      );
    }
  }
  return result;
}

String? _nonEmpty(String? value) =>
    (value == null || value.isEmpty || value == 'null') ? null : value;

/// The licence identifiers named in [expression], operators removed.
List<String> licenceIdsOf(String expression) {
  if (_knownBareDeclarations.contains(expression)) return [expression];
  return expression
      .replaceAll('(', ' ')
      .replaceAll(')', ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .where((t) {
        final upper = t.toUpperCase();
        return upper != 'AND' && upper != 'OR' && upper != 'WITH';
      })
      .toList();
}

/// `<class>/<family>` owning [rel], or null when it is not algorithm code.
String? familyOf(String rel) {
  final parts = rel.split('/');
  // At least src/<class>/<family>/<file>: liboqs' own dispatchers sit directly
  // in src/kem/ and src/sig/, and `src/kem/kem.c` names no family.
  if (parts.length < 4) return null;
  if (parts[0] != 'src') return null;
  if (parts[1] != 'kem' && parts[1] != 'sig') return null;
  return '${parts[1]}/${parts[2]}';
}

// ============================================
// Resolution
// ============================================

/// Nearest ancestor of [rel] holding licence files, searched at or below
/// `src/`.
String? _nearestLicenceDir(String rel, Map<String, List<String>> licenceFiles) {
  var dir = rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '';
  while (dir.startsWith('src')) {
    if (licenceFiles.containsKey(dir)) return dir;
    if (!dir.contains('/')) break;
    dir = dir.substring(0, dir.lastIndexOf('/'));
  }
  return null;
}

String? _overrideFor(String rel) {
  String? best;
  for (final prefix in _licenceOverrides.keys) {
    if (rel != prefix && !rel.startsWith('$prefix/')) continue;
    if (best == null || prefix.length > best.length) best = prefix;
  }
  return best;
}

String _fileNameOf(String path) => path.split('/').last;

/// Resolve one source file through A -> B -> C -> D.
LicenceResolution resolveSource({
  required String root,
  required String rel,
  required Map<String, List<String>> licenceFiles,
  required Map<String, FamilyLicence> families,
}) {
  final content = _readTextOrEmpty('$root/$rel');
  final declared = declaredLicence(content, path: rel);
  final licenceDir = _nearestLicenceDir(rel, licenceFiles);
  final copyrights = copyrightLines(content);

  final texts = <String>[];
  final origins = <String>[];
  if (licenceDir != null) {
    for (final path in licenceFiles[licenceDir]!) {
      final text = _readTextOrEmpty('$root/$path').trim();
      if (text.isEmpty) continue;
      texts.add(text);
      origins.add(_fileNameOf(path));
    }
  }

  // A header that states the terms itself only matters where no licence file
  // does; where one exists it is the same grant said twice.
  final inline = texts.isEmpty ? leadingNotice(content) : null;

  if (declared != null) {
    return LicenceResolution(
      expression: declared,
      provenance: texts.isEmpty
          ? 'an SPDX-License-Identifier tag in the sources'
          : 'an SPDX-License-Identifier tag in the sources, with the licence '
                'text shipped alongside them',
      texts: texts,
      notices: inline == null ? const [] : [inline],
      textOrigins: origins,
      copyrights: copyrights,
    );
  }

  if (texts.isNotEmpty) {
    return LicenceResolution(
      expression: _expressionForTexts(texts, licenceDir!),
      provenance: 'the licence file liboqs ships beside the sources',
      texts: texts,
      textOrigins: origins,
      copyrights: copyrights,
    );
  }

  final family = familyOf(rel);
  final familyLicence = family == null ? null : families[family];
  if (familyLicence?.expression != null) {
    return LicenceResolution(
      expression: familyLicence!.expression!,
      provenance: 'docs/algorithms/$family.yml in the liboqs sources',
      texts: const [],
      notices: inline == null ? const [] : [inline],
      copyrights: copyrights,
    );
  }

  final overrideKey = _overrideFor(rel);
  if (overrideKey != null) {
    final override = _licenceOverrides[overrideKey]!;
    return LicenceResolution(
      expression: override.expression,
      provenance: 'this package, on the basis that ${override.evidence}',
      texts: const [],
      notices: inline == null ? const [] : [inline],
      copyrights: copyrights,
    );
  }

  throw StateError(
    'No licence could be established for $rel.\n'
    'It declares no SPDX identifier, has no LICENSE/NOTICE file above it '
    'inside src/, belongs to no algorithm family documented in '
    'docs/algorithms/, and matches no entry in _licenceOverrides.\n'
    'Read the file, then record what it is licensed under in '
    'scripts/src/third_party_notices.dart.',
  );
}

/// Phrases that identify a licence inside a licence text, and what they mean.
///
/// Used only to classify a directory whose sources declare nothing themselves,
/// so the text is the whole of the evidence.
const _licenceTextMarkers = <String, String>{
  'Apache License': 'Apache-2.0',
  'Apache 2.0 License': 'Apache-2.0',
  'Creative Commons Legal Code': 'CC0-1.0',
  'CC0 1.0': 'CC0-1.0',
  'Permission is hereby granted, free of charge': 'MIT',
  'MIT license': 'MIT',
  'MIT License': 'MIT',
  'public domain': 'Public domain',
  'Public Domain': 'Public domain',
  'Redistribution and use in source and binary forms': 'BSD-3-Clause',
};

/// Licence texts that grant under more than one licence, where the connective
/// cannot be read off the text mechanically.
///
/// Keyed by a phrase unique to the text rather than by a directory, because
/// liboqs ships each of these once per implementation variant and the paths
/// change between releases while the text does not. Both entries were read by
/// a person; without them the classifier below would report only whichever
/// licence it happened to match first and understate the grant.
const _multiLicenceTexts = <String, String>{
  // The file opens "This ARMv8 NEON implementation is provided under the
  // Apache 2.0 license:" and then reproduces the original Falcon MIT notice —
  // different parts of the same directory under different licences, so both
  // apply.
  'This ARMv8 NEON implementation is provided under the Apache 2.0 license':
      'Apache-2.0 AND MIT',
  // "Public Domain (https://creativecommons.org/share-your-work/public-domain/
  // cc0/); or Apache 2.0 License" — a choice offered by upstream, not a
  // conjunction.
  'share-your-work/public-domain/cc0/': 'CC0-1.0 OR Apache-2.0',
};

/// Licence expression implied by a directory that ships its own licence text.
///
/// Only reached when no source in the directory declares one, so the text is
/// all there is. Reporting the first phrase that matches would understate a
/// text that grants under two licences — liboqs ships two such — so a text
/// matching several is a hard error unless a person has recorded what it means.
String _expressionForTexts(List<String> texts, String licenceDir) {
  final text = texts.join('\n');

  for (final entry in _multiLicenceTexts.entries) {
    if (text.contains(entry.key)) return entry.value;
  }

  final found = <String>{};
  for (final entry in _licenceTextMarkers.entries) {
    if (text.contains(entry.key)) found.add(entry.value);
  }

  if (found.length == 1) return found.single;
  if (found.isEmpty) {
    throw StateError(
      'Could not classify the licence text in $licenceDir/. Add a phrase to '
      '_licenceTextMarkers in scripts/src/third_party_notices.dart after '
      'reading it.',
    );
  }
  throw StateError(
    'The licence text in $licenceDir/ names more than one licence '
    '(${(found.toList()..sort()).join(', ')}), and how they combine cannot be '
    'read off the text — "or" and "and" both occur in liboqs. Read it, then '
    'record the expression in _multiLicenceTexts in '
    'scripts/src/third_party_notices.dart, keyed by a phrase unique to it.',
  );
}

String _readTextOrEmpty(String path) {
  try {
    return File(path).readAsStringSync();
  } on FileSystemException {
    return '';
  } on FormatException {
    // Not UTF-8; it cannot carry a readable notice.
    return '';
  }
}

// ============================================
// Grouping
// ============================================

/// Collapse per-file resolutions into the entries the document lists.
///
/// A directory whose entire subtree resolves to one licence becomes one entry;
/// a directory mixing licences is descended into, and the files sitting
/// directly in it are grouped by licence. That is what keeps BIKE readable:
/// `src/kem/bike/additional_r4/` is one Apache-2.0 entry, while the
/// BSD-3-Clause `functions_renaming.h` beside it gets its own.
List<NoticeComponent> groupComponents({
  required Map<String, LicenceResolution> byFile,
  required Map<String, FamilyLicence> families,
}) {
  final keysByDir = <String, Set<String>>{};
  final filesByDir = <String, List<String>>{};
  final filesUnderDir = <String, List<String>>{};

  for (final entry in byFile.entries) {
    final rel = entry.key;
    final dir = rel.substring(0, rel.lastIndexOf('/'));
    filesByDir.putIfAbsent(dir, () => []).add(rel);

    var current = dir;
    while (true) {
      keysByDir.putIfAbsent(current, () => {}).add(entry.value.key);
      filesUnderDir.putIfAbsent(current, () => []).add(rel);
      if (!current.contains('/')) break;
      current = current.substring(0, current.lastIndexOf('/'));
    }
  }

  final components = <NoticeComponent>[];

  void emit(List<String> paths, List<String> coveredFiles) {
    final resolution = byFile[coveredFiles.first]!;
    final provenances =
        coveredFiles.map((f) => byFile[f]!.provenance).toSet().toList()..sort();
    final copyrights =
        coveredFiles.expand((f) => byFile[f]!.copyrights).toSet().toList()
          ..sort();
    final notices =
        coveredFiles.expand((f) => byFile[f]!.notices).toSet().toList()..sort();

    String? upstream;
    if (resolution.texts.isEmpty) {
      for (final file in coveredFiles) {
        final family = familyOf(file);
        final source = family == null ? null : families[family]?.source;
        if (source != null) {
          upstream = source;
          break;
        }
      }
    }

    components.add(
      NoticeComponent(
        paths: paths,
        resolution: resolution,
        provenances: provenances,
        copyrights: copyrights,
        notices: notices,
        upstream: upstream,
      ),
    );
  }

  void walk(String dir) {
    final keys = keysByDir[dir];
    if (keys == null) return;

    if (keys.length == 1) {
      emit(['$dir/'], filesUnderDir[dir]!);
      return;
    }

    // Mixed subtree: group this directory's own files, then descend.
    final own = filesByDir[dir] ?? const <String>[];
    final grouped = <String, List<String>>{};
    for (final file in own) {
      grouped.putIfAbsent(byFile[file]!.key, () => []).add(file);
    }
    for (final key in grouped.keys.toList()..sort()) {
      final files = grouped[key]!..sort();
      emit(files, files);
    }

    final children =
        keysByDir.keys
            .where((d) => d.startsWith('$dir/'))
            .where((d) => !d.substring(dir.length + 1).contains('/'))
            .toList()
          ..sort();

    // Sibling directories under one licence become one entry. Without this a
    // family like src/sig/cross/ yields an entry per implementation variant —
    // 49 of them, all CC0-1.0, differing only in which SIMD extension they
    // target. The directories are still listed individually, so nothing is
    // hidden; they simply share a heading.
    final uniform = <String, List<String>>{};
    final mixed = <String>[];
    for (final child in children) {
      final childKeys = keysByDir[child]!;
      if (childKeys.length == 1) {
        uniform.putIfAbsent(childKeys.single, () => []).add(child);
      } else {
        mixed.add(child);
      }
    }
    for (final key in uniform.keys.toList()..sort()) {
      final dirs = uniform[key]!..sort();
      emit(
        dirs.map((d) => '$d/').toList(),
        dirs.expand((d) => filesUnderDir[d]!).toList(),
      );
    }

    for (final child in mixed) {
      walk(child);
    }
  }

  walk('src');
  components.sort((a, b) => a.paths.first.compareTo(b.paths.first));
  return components;
}

// ============================================
// Rendering
// ============================================

const _rule =
    '=============================================================='
    '================';
const _thinRule =
    '--------------------------------------------------------------'
    '----------------';

/// Render the inventory as the committed `THIRD_PARTY_NOTICES.txt`.
String renderNotices(NoticeInventory inventory) {
  final buffer = StringBuffer();

  // Pool the licence texts: the tree holds 153 licence files but only 15
  // distinct texts, so printing them per component would repeat the Apache-2.0
  // text a dozen times over.
  final users = <String, List<String>>{};
  final origins = <String, Set<String>>{};
  for (final component in inventory.components) {
    final resolution = component.resolution;
    for (var i = 0; i < resolution.texts.length; i++) {
      final text = resolution.texts[i];
      users.putIfAbsent(text, () => []).addAll(component.paths);
      if (i < resolution.textOrigins.length) {
        origins.putIfAbsent(text, () => {}).add(resolution.textOrigins[i]);
      }
    }
    for (final notice in component.notices) {
      users.putIfAbsent(notice, () => []).addAll(component.paths);
      origins.putIfAbsent(notice, () => {}).add('source header');
    }
  }

  // Indices follow content order, so the numbering is a function of the texts
  // alone rather than of the order components happen to be walked in.
  final ordered = users.keys.toList()..sort();
  final indexOf = <String, int>{};
  for (var i = 0; i < ordered.length; i++) {
    indexOf[ordered[i]] = i + 1;
  }

  // Where one licence identifier's full text lives in the pool. Built only from
  // components whose licence file states exactly one licence, so the mapping is
  // never guessed from a disjunction. It is what lets a component that ships no
  // licence text of its own — `src/common/common.c` is Apache-2.0 AND MIT and
  // has none — still point a reader at the terms it is bound by.
  final textForId = <String, int>{};
  for (final component in inventory.components) {
    final ids = licenceIdsOf(component.resolution.expression);
    if (ids.length != 1) continue;
    if (component.resolution.texts.isEmpty) continue;
    final index = indexOf[component.resolution.texts.first];
    if (index != null) textForId.putIfAbsent(ids.single, () => index);
  }

  buffer
    ..writeln('THIRD-PARTY SOFTWARE NOTICES')
    ..writeln()
    ..writeln(
      'The liboqs package ships a prebuilt native library compiled from the',
    )
    ..writeln(
      'liboqs C sources. liboqs vendors code from many upstream projects, and',
    )
    ..writeln(
      'its own LICENSE.txt says as much: "liboqs includes some third party',
    )
    ..writeln(
      'libraries or modules that are licensed differently; the corresponding',
    )
    ..writeln(
      'subfolder contains the license that applies in that case." Those',
    )
    ..writeln(
      'licences require these notices to accompany any binary distribution,',
    )
    ..writeln('including an application that embeds the library.')
    ..writeln()
    ..writeln('Generated from liboqs ${inventory.liboqsVersion}.')
    ..writeln()
    ..writeln(
      "liboqs' own MIT licence is not repeated here; it ships beside this file",
    )
    ..writeln('as LICENSE.liboqs.')
    ..writeln()
    ..writeln(
      'Scope: every source under src/, except as noted below. That is a',
    )
    ..writeln(
      'superset of what any single platform compiles, and it yields the same',
    )
    ..writeln(
      'set of licences as the union over all eleven artifacts this package',
    )
    ..writeln('ships.');
  for (final entry in _excludedPaths.entries) {
    buffer.writeln('Excluded: ${entry.key} — ${entry.value}.');
  }
  buffer
    ..writeln()
    ..writeln(
      'Each component records where its licence was established: a tag in the',
    )
    ..writeln(
      'sources, a licence file shipped beside them, the algorithm metadata in',
    )
    ..writeln(
      'docs/algorithms/, or a determination recorded by this package. Licence',
    )
    ..writeln(
      'texts are pooled below and referenced as [T1], [T2], … because one text',
    )
    ..writeln('commonly covers many components.')
    ..writeln()
    ..writeln('Regenerate with `make third-party-notices`.')
    ..writeln()
    ..writeln('Components listed: ${inventory.components.length}')
    ..writeln('Distinct licence texts: ${ordered.length}')
    ..writeln()
    ..writeln(_rule)
    ..writeln('COMPONENTS')
    ..writeln(_rule);

  for (final component in inventory.components) {
    buffer.writeln();
    for (final path in component.paths) {
      buffer.writeln(path);
    }
    buffer
      ..writeln('  License:     ${component.resolution.expression}')
      ..writeln('  Declared in: ${component.provenances.join('; ')}');

    for (var i = 0; i < component.copyrights.length; i++) {
      final label = i == 0 ? '  Copyright:  ' : '               ';
      buffer.writeln('$label ${component.copyrights[i]}');
    }

    final refs = <String>[];
    for (var i = 0; i < component.resolution.texts.length; i++) {
      final index = indexOf[component.resolution.texts[i]];
      if (index == null) continue;
      final origin = i < component.resolution.textOrigins.length
          ? component.resolution.textOrigins[i]
          : 'licence file';
      refs.add('$origin [T$index]');
    }
    for (final notice in component.notices) {
      final index = indexOf[notice];
      if (index != null) refs.add('source header [T$index]');
    }
    if (refs.isNotEmpty) {
      buffer.writeln('  Texts:       ${refs.join(', ')}');
    } else {
      buffer.writeln(
        '  Texts:       liboqs ships no licence text for this component',
      );
      final elsewhere = <String>[];
      for (final id in licenceIdsOf(component.resolution.expression)) {
        final index = textForId[id];
        if (index != null) elsewhere.add('$id [T$index]');
      }
      if (elsewhere.isNotEmpty) {
        buffer.writeln(
          '  Terms:       as shipped elsewhere in liboqs — '
          '${elsewhere.join(', ')}',
        );
      }
    }
    if (component.upstream != null) {
      buffer.writeln('  Upstream:    ${component.upstream}');
    }
  }

  buffer
    ..writeln()
    ..writeln(_rule)
    ..writeln('LICENCE TEXTS')
    ..writeln(_rule)
    ..writeln()
    ..writeln('Texts exactly as liboqs ships them.');

  for (final text in ordered) {
    final index = indexOf[text]!;
    final covered = users[text]!.toSet().toList()..sort();
    final origin = (origins[text]?.toList()?..sort()) ?? const <String>[];
    buffer
      ..writeln()
      ..writeln(_thinRule)
      // Paths, not components: one component can list dozens of implementation
      // directories, so counting components here would report a number that
      // does not match the list underneath it.
      ..writeln('[T$index] applies to ${covered.length} path(s)')
      ..writeln(_thinRule)
      ..writeln();
    if (origin.isNotEmpty) {
      buffer.writeln('Read from: ${origin.join(', ')}');
    }
    buffer.writeln('Applies to:');
    for (final path in covered) {
      buffer.writeln('  $path');
    }
    buffer
      ..writeln()
      ..writeln(text);
  }

  return buffer.toString();
}

// ============================================
// Source tree
// ============================================

/// Where the liboqs checkout used for generation is kept.
///
/// Separate from the `make build` clone so regenerating notices never disturbs
/// an in-progress native build, and keyed by version so a bump gets a fresh
/// tree rather than a stale one.
String noticesSourceDir(String version) =>
    '${getTempBuildDir()}-notices/liboqs-$version';

/// Clone liboqs at [version], reusing an existing checkout.
Future<String> ensureSourceTree({
  required String version,
  bool refresh = false,
  bool silent = false,
}) async {
  final target = noticesSourceDir(version);
  final dir = Directory(target);

  if (refresh && dir.existsSync()) {
    await removeDir(target);
  }
  if (dir.existsSync() && Directory('$target/src').existsSync()) {
    if (!silent) logInfo('Using cached liboqs $version checkout at $target');
    return target;
  }

  if (dir.existsSync()) await removeDir(target);
  await ensureDir(Directory(target).parent.path);
  if (!silent) logStep('Cloning liboqs $version...');

  // Retried, unlike the plain `gitClone` the build scripts use. This clone sits
  // under three gates that all fail closed — the test job, the native-build
  // gate and both release preflights — so a transient network blip would
  // otherwise read as "the notices are wrong". A partial clone is removed
  // before each attempt so a retry never resumes into a half-populated tree.
  const maxAttempts = 3;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await gitClone(
        url: 'https://github.com/open-quantum-safe/liboqs.git',
        targetDir: target,
        branch: version,
      );
      return target;
    } catch (e) {
      if (dir.existsSync()) await removeDir(target);
      if (attempt == maxAttempts) {
        throw StateError(
          'Could not clone liboqs $version after $maxAttempts attempts: $e\n'
          'The notice inventory is derived from those sources, so it cannot be '
          'generated or verified without them.',
        );
      }
      if (!silent) {
        logWarn('Clone attempt $attempt failed, retrying: $e');
      }
      await Future<void>.delayed(Duration(seconds: 2 * attempt));
    }
  }
  return target;
}

// ============================================
// Entry points
// ============================================

/// Path of the committed notices file.
String noticesPath() => '${getPackageDir().path}/THIRD_PARTY_NOTICES.txt';

/// Build the notices document for the pinned liboqs version.
Future<String> generateNotices({
  bool refresh = false,
  bool silent = false,
}) async {
  final version = getLiboqsVersion();
  final root = await ensureSourceTree(
    version: version,
    refresh: refresh,
    silent: silent,
  );

  if (!silent) logStep('Resolving licences...');
  final licenceFiles = collectLicenceFiles(root);
  final families = collectFamilyLicences(root);
  final sources = collectSources(root);

  final byFile = <String, LicenceResolution>{};
  for (final rel in sources) {
    byFile[rel] = resolveSource(
      root: root,
      rel: rel,
      licenceFiles: licenceFiles,
      families: families,
    );
  }

  final components = groupComponents(byFile: byFile, families: families);
  if (!silent) {
    logInfo('${sources.length} sources -> ${components.length} components');
  }

  return renderNotices(
    NoticeInventory(liboqsVersion: version, components: components),
  );
}

// ============================================
// Drift reporting
// ============================================

/// Describe how the committed file differs from [generated], or null when they
/// match byte for byte.
///
/// This runs where nobody is watching — a CI job and two release preflights —
/// so the message has to be the whole diagnosis rather than "they differ".
String? describeDrift({required String generated, required String path}) {
  final file = File(path);
  if (!file.existsSync()) {
    return 'Missing $path. Run `make third-party-notices`.';
  }

  final committed = file.readAsStringSync();
  if (committed == generated) return null;

  final committedCount = _componentCount(committed);
  final generatedCount = _componentCount(generated);
  final detail = committedCount == generatedCount
      ? 'same component count ($committedCount), but the contents differ — a '
            'liboqs version, a licence text or the generator itself changed'
      : 'lists $committedCount components, the liboqs sources resolve to '
            '$generatedCount';

  final buffer = StringBuffer()
    ..writeln('Committed $path is out of date ($detail).');

  final committedLines = const LineSplitter().convert(committed);
  final generatedLines = const LineSplitter().convert(generated);
  for (var i = 0; i < committedLines.length || i < generatedLines.length; i++) {
    final a = i < committedLines.length ? committedLines[i] : '<end of file>';
    final b = i < generatedLines.length ? generatedLines[i] : '<end of file>';
    if (a != b) {
      buffer
        ..writeln('  First difference at line ${i + 1}:')
        ..writeln('    committed: $a')
        ..writeln('    generated: $b');
      break;
    }
  }

  buffer.write('Run `make third-party-notices` and commit the result.');
  return buffer.toString();
}

int _componentCount(String document) {
  final match = RegExp(
    r'^Components listed: (\d+)$',
    multiLine: true,
  ).firstMatch(document);
  return match == null ? -1 : int.parse(match.group(1)!);
}

/// Abort a release when the committed notices do not match the pinned sources.
Future<void> assertNoticesCurrent() async {
  final generated = await generateNotices(silent: true);
  final drift = describeDrift(generated: generated, path: noticesPath());
  if (drift != null) {
    throw StateError(
      '$drift\n'
      'This file ships in the release archives and in the published package, '
      'so the release is aborted.',
    );
  }
}
