import 'dart:io';

import 'package:test/test.dart';

import '../../scripts/src/third_party_notices.dart';

/// Builds a throwaway liboqs-shaped tree so the resolver can be exercised
/// without a 79 MB clone. Only the parts the generator reads are created:
/// `src/`, licence files, and `docs/algorithms/`.
class _Tree {
  final Directory dir;

  _Tree() : dir = Directory.systemTemp.createTempSync('liboqs-notices-test');

  String get root => dir.path;

  void write(String rel, String content) {
    final file = File('$root/$rel');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void dispose() => dir.deleteSync(recursive: true);
}

/// The shape of a real liboqs source: an SPDX tag over a banner comment.
String _source(String spdx, {String? copyright}) =>
    '// SPDX-License-Identifier: $spdx\n'
    '${copyright == null ? '' : '/*\n * $copyright\n */\n'}'
    'int placeholder(void);\n';

const _mitText = '''
MIT License

Copyright (c) 2020 Example

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software.''';

const _apacheText = '''
                                 Apache License
                           Version 2.0, January 2004''';

void main() {
  group('declaredLicence', () {
    test('reads a plain identifier', () {
      expect(
        declaredLicence('// SPDX-License-Identifier: MIT\n', path: 'a.c'),
        'MIT',
      );
    });

    test('reads a conjunction, which is not the same as a choice', () {
      expect(
        declaredLicence(
          '// SPDX-License-Identifier: Apache-2.0 AND MIT\n',
          path: 'src/common/common.c',
        ),
        'Apache-2.0 AND MIT',
      );
    });

    test('normalises the stray quote upstream leaves in BIKE', () {
      expect(
        declaredLicence(
          ' * SPDX-License-Identifier: Apache-2.0"\n',
          path: 'src/kem/bike/additional_r4/shake_prf.c',
        ),
        'Apache-2.0',
      );
    });

    test('skips a mangled tag when the file also carries an intact one', () {
      // Upstream spliced an SPDX line into the middle of a BSD notice; the
      // clean tag sits at the bottom of the same comment.
      const content = '''
/*
 * SPDX-License-Identifier: BSD-3-Clauseing disclaimer in the
 *   documentation and/or other materials provided with the distribution.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */
''';
      expect(
        declaredLicence(content, path: 'src/kem/bike/functions_renaming.h'),
        'BSD-3-Clause',
      );
    });

    test('returns null when the file declares nothing', () {
      expect(declaredLicence('int main(void);\n', path: 'a.c'), isNull);
    });

    test('throws when the only declaration is unreadable', () {
      // A new liboqs release vendoring an unfamiliar licence must stop the
      // generator rather than be filed under whatever is nearest.
      expect(
        () => declaredLicence(
          '// SPDX-License-Identifier: WTFPL-9.9\n',
          path: 'src/kem/new/thing.c',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('isKnownDeclaration', () {
    test('accepts expressions built from known identifiers', () {
      expect(isKnownDeclaration('CC0 OR Apache-2.0'), isTrue);
      expect(isKnownDeclaration('Apache-2.0 OR ISC OR MIT'), isTrue);
      expect(isKnownDeclaration('Public domain'), isTrue);
    });

    test('rejects prose that merely looks like identifiers', () {
      expect(isKnownDeclaration('BSD-3-Clauseing disclaimer in the'), isFalse);
      expect(isKnownDeclaration('Unknown'), isFalse);
    });
  });

  group('licenceIdsOf', () {
    test('drops the operators', () {
      expect(licenceIdsOf('Apache-2.0 AND MIT'), ['Apache-2.0', 'MIT']);
      expect(licenceIdsOf('Apache-2.0 OR ISC OR MIT'), [
        'Apache-2.0',
        'ISC',
        'MIT',
      ]);
    });

    test('keeps a bare declaration whole', () {
      expect(licenceIdsOf('Public domain'), ['Public domain']);
    });
  });

  group('leadingNotice', () {
    test('keeps a header that states the terms', () {
      const content = '''
/*
 * Copyright (c) 2017 Someone
 *
 * Redistribution and use in source and binary forms are permitted.
 */
int f(void);
''';
      final notice = leadingNotice(content);
      expect(notice, isNotNull);
      expect(notice, contains('Redistribution and use'));
      expect(notice, isNot(contains('*')));
    });

    test('ignores a header that is only an attribution banner', () {
      // Nearly every liboqs source opens like this. Embedding them all would
      // add twenty near-identical banners and no grant.
      const content = '''
/*
 * Copyright (c) 2021 The Open Quantum Safe project authors
 */
int f(void);
''';
      expect(leadingNotice(content), isNull);
    });

    test('ignores line comments', () {
      expect(leadingNotice('// Copyright (c) 2021 Someone\n'), isNull);
    });
  });

  group('copyrightLines', () {
    test('collects and de-duplicates holders across comment styles', () {
      const content = '''
# Copyright (c) 2006-2017, CRYPTOGAMS by <appro@openssl.org>
# Copyright (c) 2017 Ronny Van Keer
# Copyright (c) 2017 Ronny Van Keer
''';
      expect(copyrightLines(content), [
        'Copyright (c) 2006-2017, CRYPTOGAMS by <appro@openssl.org>',
        'Copyright (c) 2017 Ronny Van Keer',
      ]);
    });

    test('skips a bare heading that names no holder', () {
      expect(copyrightLines('/* Copyright */\n'), isEmpty);
    });
  });

  group('collectSources', () {
    late _Tree tree;

    setUp(() {
      tree = _Tree();
      tree.write('src/kem/ml_kem/kem.c', _source('MIT'));
      tree.write('src/kem/ml_kem/kem.h', _source('MIT'));
      tree.write('src/kem/ml_kem/notes.md', 'not source');
      tree.write('src/common/aes/aes_ni.S', _source('MIT'));
    });

    tearDown(() => tree.dispose());

    test('takes C sources, headers and assembly, and nothing else', () {
      expect(collectSources(tree.root), [
        'src/common/aes/aes_ni.S',
        'src/kem/ml_kem/kem.c',
        'src/kem/ml_kem/kem.h',
      ]);
    });

    test('leaves out the stateful signatures this package never builds', () {
      tree.write('src/sig_stfl/xmss/xmss.c', _source('MIT'));
      expect(
        collectSources(tree.root),
        isNot(contains('src/sig_stfl/xmss/xmss.c')),
      );
    });

    test('leaves out the test-only NIST RNG', () {
      // Compiled into liboqs' `internal` object library, never linked into the
      // shared library this package ships.
      tree.write('src/common/rand/rand_nist.c', _source('MIT'));
      expect(
        collectSources(tree.root),
        isNot(contains('src/common/rand/rand_nist.c')),
      );
    });
  });

  group('collectLicenceFiles', () {
    late _Tree tree;

    setUp(() {
      tree = _Tree();
      tree.write('src/kem/bike/additional_r4/decode.c', _source('Apache-2.0'));
      tree.write('src/kem/bike/additional_r4/LICENSE', _apacheText);
      tree.write('src/sig/mayo/impl/NOTICE', 'Copyright 2023 the MAYO team');
      tree.write('src/sig/mayo/impl/mayo.c', _source('Apache-2.0'));
      tree.write('LICENSE.txt', _mitText);
    });

    tearDown(() => tree.dispose());

    test('finds LICENSE and NOTICE files under src/', () {
      final found = collectLicenceFiles(tree.root);
      expect(found['src/kem/bike/additional_r4'], [
        'src/kem/bike/additional_r4/LICENSE',
      ]);
      expect(found['src/sig/mayo/impl'], ['src/sig/mayo/impl/NOTICE']);
    });

    test('never offers the root licence as a fallback', () {
      // liboqs' own MIT covers liboqs' own code. Letting it stand in for every
      // orphan source is the misattribution this generator exists to prevent.
      expect(collectLicenceFiles(tree.root).keys, isNot(contains('')));
    });
  });

  group('collectFamilyLicences', () {
    late _Tree tree;

    setUp(() {
      tree = _Tree();
      tree.write('src/kem/frodokem/external/kem.c', 'int f(void);\n');
      tree.write('docs/algorithms/kem/frodokem.yml', '''
name: FrodoKEM
oqs-support-tier: 2
primary-upstream:
  source: https://github.com/microsoft/PQCrypto-LWEKE/commit/a2f9dec
  spdx-license-identifier: MIT
parameter-sets:
- name: FrodoKEM-640-AES
''');
      tree.write('docs/algorithms/sig/lms.yml', '''
name: LMS
primary-upstream:
  spdx-license-identifier: null
''');
    });

    tearDown(() => tree.dispose());

    test('reads the licence and upstream of a family', () {
      final families = collectFamilyLicences(tree.root);
      expect(families['kem/frodokem']!.expression, 'MIT');
      expect(
        families['kem/frodokem']!.source,
        'https://github.com/microsoft/PQCrypto-LWEKE/commit/a2f9dec',
      );
    });

    test('treats an explicit null as absent', () {
      expect(collectFamilyLicences(tree.root)['sig/lms']!.expression, isNull);
    });

    test('stops at the primary-upstream block', () {
      // `parameter-sets` follows it and also has `name:` keys; a greedy match
      // would swallow them.
      expect(
        collectFamilyLicences(tree.root)['kem/frodokem']!.expression,
        'MIT',
      );
    });
  });

  group('familyOf', () {
    test('names the algorithm family owning a source', () {
      expect(familyOf('src/kem/frodokem/external/kem.c'), 'kem/frodokem');
      expect(familyOf('src/sig/uov/pqov_ov_Is_ref/ov.c'), 'sig/uov');
    });

    test('returns null for code that is not an algorithm', () {
      expect(familyOf('src/common/common.c'), isNull);
      expect(familyOf('src/kem/kem.c'), isNull);
    });
  });

  group('resolveSource', () {
    late _Tree tree;

    LicenceResolution resolve(String rel) => resolveSource(
      root: tree.root,
      rel: rel,
      licenceFiles: collectLicenceFiles(tree.root),
      families: collectFamilyLicences(tree.root),
    );

    setUp(() => tree = _Tree());
    tearDown(() => tree.dispose());

    test('A — the tag in the file wins over the licence file beside it', () {
      // BIKE ships an Apache-2.0 LICENSE, but this header is BSD-3-Clause and
      // says so. Deferring to the directory would lose a whole licence.
      tree.write('src/kem/bike/additional_r4/LICENSE', _apacheText);
      tree.write(
        'src/kem/bike/additional_r4/odd.h',
        '// SPDX-License-Identifier: BSD-3-Clause\nint f(void);\n',
      );
      expect(
        resolve('src/kem/bike/additional_r4/odd.h').expression,
        'BSD-3-Clause',
      );
    });

    test(
      'B — the licence file classifies a directory that declares nothing',
      () {
        tree.write('src/sig/snova/impl/LICENSE', _mitText);
        tree.write('src/sig/snova/impl/snova.c', 'int f(void);\n');
        final resolution = resolve('src/sig/snova/impl/snova.c');
        expect(resolution.expression, 'MIT');
        expect(
          resolution.texts.single,
          contains('Permission is hereby granted'),
        );
      },
    );

    test('B — a text naming two licences is not reported as one', () {
      // liboqs ships two such texts. Classifying by the first phrase that
      // matches would silently report half the grant, which is the one thing
      // this document must not do — so an unrecorded multi-licence text is a
      // hard error rather than a guess.
      tree.write('src/kem/mixed/impl/LICENSE', '''
$_mitText

This part is also covered by the Apache License, Version 2.0.''');
      tree.write('src/kem/mixed/impl/thing.c', 'int f(void);\n');
      expect(
        () => resolve('src/kem/mixed/impl/thing.c'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('more than one licence'), contains('Apache-2.0')),
          ),
        ),
      );
    });

    test('B — a recorded multi-licence text keeps its connective', () {
      // Falcon's ARMv8 directory grants under both; pqcrystals-kyber offers a
      // choice. AND and OR are not interchangeable, and neither can be read off
      // the text mechanically, so both are recorded by hand.
      tree.write(
        'src/sig/falcon/pqclean_falcon-512_aarch64/LICENSE',
        'This ARMv8 NEON implementation is provided under the Apache 2.0 '
            'license:\n$_apacheText\n$_mitText',
      );
      tree.write(
        'src/sig/falcon/pqclean_falcon-512_aarch64/inner.c',
        'int f(void);\n',
      );
      expect(
        resolve('src/sig/falcon/pqclean_falcon-512_aarch64/inner.c').expression,
        'Apache-2.0 AND MIT',
      );

      tree.write(
        'src/kem/kyber/pqcrystals-kyber_kyber512_ref/LICENSE',
        'Public Domain '
            '(https://creativecommons.org/share-your-work/public-domain/cc0/); '
            'or Apache 2.0 License',
      );
      tree.write(
        'src/kem/kyber/pqcrystals-kyber_kyber512_ref/kem.c',
        'int f(void);\n',
      );
      expect(
        resolve('src/kem/kyber/pqcrystals-kyber_kyber512_ref/kem.c').expression,
        'CC0-1.0 OR Apache-2.0',
      );
    });

    test('C — the algorithm metadata covers code with neither', () {
      // FrodoKEM and HQC state their licence only in docs/algorithms/.
      tree.write('src/kem/frodokem/external/kem.c', 'int f(void);\n');
      tree.write('docs/algorithms/kem/frodokem.yml', '''
primary-upstream:
  source: https://github.com/microsoft/PQCrypto-LWEKE
  spdx-license-identifier: MIT
''');
      final resolution = resolve('src/kem/frodokem/external/kem.c');
      expect(resolution.expression, 'MIT');
      expect(resolution.provenance, contains('docs/algorithms'));
      expect(resolution.texts, isEmpty);
    });

    test('D — an override covers in-tree code nothing else states', () {
      tree.write(
        'src/common/sha3/xkcp_low/KeccakP-1600/opt64.c',
        '/*\n * To the extent possible under law, the implementer has\n'
            ' * waived all copyright.\n */\nint f(void);\n',
      );
      final resolution = resolve(
        'src/common/sha3/xkcp_low/KeccakP-1600/opt64.c',
      );
      expect(resolution.expression, 'CC0-1.0');
      expect(resolution.provenance, contains('this package'));
      expect(resolution.notices.single, contains('waived all copyright'));
    });

    test(
      'D — the longest override wins, carving one file out of a subtree',
      () {
        // The CRYPTOGAMS assembly sits inside the XKCP tree but is not under
        // XKCP's CC0 waiver.
        tree.write(
          'src/common/sha3/xkcp_low/KeccakP-1600/avx2/KeccakP-1600-AVX2.S',
          '# Copyright (c) 2006-2017, CRYPTOGAMS by <appro@openssl.org>\n',
        );
        expect(
          resolve(
            'src/common/sha3/xkcp_low/KeccakP-1600/avx2/KeccakP-1600-AVX2.S',
          ).expression,
          'LicenseRef-CRYPTOGAMS',
        );
      },
    );

    test('throws rather than silently attributing an orphan source', () {
      tree.write('src/kem/mystery/impl/thing.c', 'int f(void);\n');
      expect(
        () => resolve('src/kem/mystery/impl/thing.c'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('groupComponents', () {
    LicenceResolution resolution(String expression, {List<String>? texts}) =>
        LicenceResolution(
          expression: expression,
          provenance: 'a tag',
          texts: texts ?? const [],
        );

    test('collapses a subtree up to the point the licence changes', () {
      final components = groupComponents(
        byFile: {
          'src/sig/snova/a/x.c': resolution('MIT', texts: [_mitText]),
          'src/sig/snova/a/y.c': resolution('MIT', texts: [_mitText]),
          'src/sig/snova/b/z.c': resolution('MIT', texts: [_mitText]),
          // A differing sibling family stops the collapse at snova; without it
          // the whole of src/sig/ would legitimately become one entry.
          'src/sig/falcon/a.c': resolution('Apache-2.0'),
        },
        families: const {},
      );
      expect(components.map((c) => c.paths.single), [
        'src/sig/falcon/',
        'src/sig/snova/',
      ]);
    });

    test('merges sibling directories that share a licence', () {
      // src/sig/cross/ has 49 implementation variants, all CC0-1.0, differing
      // only in which SIMD extension they target. One entry, all listed.
      final components = groupComponents(
        byFile: {
          'src/sig/cross/sig_cross.c': resolution('MIT', texts: [_mitText]),
          'src/sig/cross/impl_avx2/a.c': resolution('CC0-1.0'),
          'src/sig/cross/impl_neon/a.c': resolution('CC0-1.0'),
          'src/sig/cross/impl_ref/a.c': resolution('CC0-1.0'),
        },
        families: const {},
      );
      final cc0 = components.firstWhere(
        (c) => c.resolution.expression == 'CC0-1.0',
      );
      expect(cc0.paths, [
        'src/sig/cross/impl_avx2/',
        'src/sig/cross/impl_neon/',
        'src/sig/cross/impl_ref/',
      ]);
    });

    test('keeps an odd file out of the entry for its siblings', () {
      final components = groupComponents(
        byFile: {
          'src/kem/bike/additional_r4/a.c': resolution('Apache-2.0'),
          'src/kem/bike/functions_renaming.h': resolution('BSD-3-Clause'),
        },
        families: const {},
      );
      expect(components.map((c) => c.paths.single), [
        'src/kem/bike/additional_r4/',
        'src/kem/bike/functions_renaming.h',
      ]);
    });

    test('gathers every distinct copyright across a collapsed component', () {
      final components = groupComponents(
        byFile: {
          'src/x/a.c': const LicenceResolution(
            expression: 'MIT',
            provenance: 'a tag',
            texts: [],
            copyrights: ['Copyright (c) 2020 Alice and friends'],
          ),
          'src/x/b.c': const LicenceResolution(
            expression: 'MIT',
            provenance: 'a tag',
            texts: [],
            copyrights: ['Copyright (c) 2021 Bob and colleagues'],
          ),
        },
        families: const {},
      );
      expect(components.single.copyrights, [
        'Copyright (c) 2020 Alice and friends',
        'Copyright (c) 2021 Bob and colleagues',
      ]);
    });
  });

  group('renderNotices', () {
    NoticeComponent component(
      String path,
      String expression, {
      List<String> texts = const [],
      List<String> copyrights = const [],
      String? upstream,
    }) => NoticeComponent(
      paths: [path],
      resolution: LicenceResolution(
        expression: expression,
        provenance: 'a tag in the sources',
        texts: texts,
        textOrigins: texts.isEmpty ? const [] : const ['LICENSE'],
      ),
      provenances: const ['a tag in the sources'],
      copyrights: copyrights,
      notices: const [],
      upstream: upstream,
    );

    test('pools a text shared by several components', () {
      final output = renderNotices(
        NoticeInventory(
          liboqsVersion: '0.16.0',
          components: [
            component('src/a/', 'MIT', texts: [_mitText]),
            component('src/b/', 'MIT', texts: [_mitText]),
          ],
        ),
      );
      expect(output, contains('Distinct licence texts: 1'));
      expect('MIT License'.allMatches(output).length, 1);
      expect(output, contains('[T1] applies to 2 path(s)'));
    });

    test('points a component with no text of its own at the pooled terms', () {
      // src/common/common.c is Apache-2.0 AND MIT and ships neither text. The
      // conjunction means Apache-2.0 binds every artifact, so the reader has to
      // be able to reach its terms.
      final output = renderNotices(
        NoticeInventory(
          liboqsVersion: '0.16.0',
          components: [
            component('src/apache/', 'Apache-2.0', texts: [_apacheText]),
            component('src/common/common.c', 'Apache-2.0 AND MIT'),
            component('src/mit/', 'MIT', texts: [_mitText]),
          ],
        ),
      );
      expect(output, contains('License:     Apache-2.0 AND MIT'));
      expect(
        output,
        contains(
          'Terms:       as shipped elsewhere in liboqs — Apache-2.0 [T1], MIT [T2]',
        ),
      );
    });

    test('never maps an identifier from a disjunction', () {
      // A directory licensed "CC0 OR Apache-2.0" shipping one text says nothing
      // about which of the two that text is.
      final output = renderNotices(
        NoticeInventory(
          liboqsVersion: '0.16.0',
          components: [
            component('src/uov/', 'CC0 OR Apache-2.0', texts: [_apacheText]),
            component('src/other/', 'Apache-2.0'),
          ],
        ),
      );
      expect(output, isNot(contains('Terms:')));
    });

    test('records the upstream project when liboqs ships no text', () {
      final output = renderNotices(
        NoticeInventory(
          liboqsVersion: '0.16.0',
          components: [
            component(
              'src/kem/frodokem/external/',
              'MIT',
              upstream: 'https://github.com/microsoft/PQCrypto-LWEKE',
            ),
          ],
        ),
      );
      expect(
        output,
        contains('Upstream:    https://github.com/microsoft/PQCrypto-LWEKE'),
      );
    });

    test('reproduces copyright lines', () {
      final output = renderNotices(
        NoticeInventory(
          liboqsVersion: '0.16.0',
          components: [
            component(
              'src/x/',
              'MIT',
              copyrights: const [
                'Copyright (c) 2017 Ronny Van Keer',
                'Copyright (c) 2020 Someone Else',
              ],
            ),
          ],
        ),
      );
      expect(
        output,
        contains('Copyright:   Copyright (c) 2017 Ronny Van Keer'),
      );
      expect(output, contains('             Copyright (c) 2020 Someone Else'));
    });

    test('stamps the liboqs version it was generated from', () {
      final output = renderNotices(
        const NoticeInventory(liboqsVersion: '0.16.0', components: []),
      );
      expect(output, contains('Generated from liboqs 0.16.0.'));
    });

    test('numbers texts by content, not by order of use', () {
      // Byte-stability across runs is what makes the committed file
      // verifiable; numbering by first use would renumber on reordering.
      String render(List<NoticeComponent> components) => renderNotices(
        NoticeInventory(liboqsVersion: '0.16.0', components: components),
      );
      final a = component('src/a/', 'MIT', texts: [_mitText]);
      final b = component('src/b/', 'Apache-2.0', texts: [_apacheText]);
      // The Apache text sorts first, so it is [T1] whichever component the
      // walk happened to reach first.
      for (final output in [
        render([a, b]),
        render([b, a]),
      ]) {
        expect(output, contains('[T1] applies to 1 path(s)'));
        expect(
          output.indexOf('Apache License'),
          lessThan(output.indexOf('MIT License')),
        );
      }
      expect(
        render([a, b]).split('LICENCE TEXTS').last,
        render([b, a]).split('LICENCE TEXTS').last,
      );
    });
  });

  group('describeDrift', () {
    late _Tree tree;

    setUp(() => tree = _Tree());
    tearDown(() => tree.dispose());

    test('reports a missing file', () {
      final drift = describeDrift(
        generated: 'anything',
        path: '${tree.root}/THIRD_PARTY_NOTICES.txt',
      );
      expect(drift, contains('Missing'));
      expect(drift, contains('make third-party-notices'));
    });

    test('returns null on a byte-exact match', () {
      tree.write('THIRD_PARTY_NOTICES.txt', 'Components listed: 2\nbody\n');
      expect(
        describeDrift(
          generated: 'Components listed: 2\nbody\n',
          path: '${tree.root}/THIRD_PARTY_NOTICES.txt',
        ),
        isNull,
      );
    });

    test('names the changed count when components appear', () {
      tree.write('THIRD_PARTY_NOTICES.txt', 'Components listed: 2\nbody\n');
      final drift = describeDrift(
        generated: 'Components listed: 3\nbody\n',
        path: '${tree.root}/THIRD_PARTY_NOTICES.txt',
      );
      expect(drift, contains('lists 2 components'));
      expect(drift, contains('resolve to 3'));
    });

    test('points at the first differing line when only content moved', () {
      tree.write('THIRD_PARTY_NOTICES.txt', 'Components listed: 2\nold\n');
      final drift = describeDrift(
        generated: 'Components listed: 2\nnew\n',
        path: '${tree.root}/THIRD_PARTY_NOTICES.txt',
      );
      expect(drift, contains('same component count (2)'));
      expect(drift, contains('First difference at line 2'));
      expect(drift, contains('committed: old'));
      expect(drift, contains('generated: new'));
    });
  });
}
