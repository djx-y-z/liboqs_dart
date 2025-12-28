import 'dart:convert';
import 'dart:typed_data';

import 'package:liboqs/liboqs.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    LibOQS.init();
  });

  tearDownAll(() {
    LibOQS.cleanup();
  });

  group('KEM Basic Operations', () {
    test('ML-KEM-512 key generation and encapsulation', () {
      final kem = KEM.create('ML-KEM-512');

      final keyPair = kem.generateKeyPair();
      expect(keyPair.publicKey.length, equals(800));
      expect(keyPair.secretKey.length, equals(1632));

      final encResult = kem.encapsulate(keyPair.publicKey);
      expect(encResult.ciphertext.length, equals(768));
      expect(encResult.sharedSecret.length, equals(32));

      final decryptedSecret = kem.decapsulate(
        encResult.ciphertext,
        keyPair.secretKey,
      );
      expect(decryptedSecret, equals(encResult.sharedSecret));

      kem.dispose();
    });

    test('ML-KEM-768 key generation and encapsulation', () {
      final kem = KEM.create('ML-KEM-768');

      final keyPair = kem.generateKeyPair();
      expect(keyPair.publicKey.length, equals(1184));
      expect(keyPair.secretKey.length, equals(2400));

      final encResult = kem.encapsulate(keyPair.publicKey);
      expect(encResult.ciphertext.length, equals(1088));
      expect(encResult.sharedSecret.length, equals(32));

      final decryptedSecret = kem.decapsulate(
        encResult.ciphertext,
        keyPair.secretKey,
      );
      expect(decryptedSecret, equals(encResult.sharedSecret));

      kem.dispose();
    });

    test('ML-KEM-1024 key generation and encapsulation', () {
      final kem = KEM.create('ML-KEM-1024');

      final keyPair = kem.generateKeyPair();
      expect(keyPair.publicKey.length, equals(1568));
      expect(keyPair.secretKey.length, equals(3168));

      final encResult = kem.encapsulate(keyPair.publicKey);
      expect(encResult.ciphertext.length, equals(1568));
      expect(encResult.sharedSecret.length, equals(32));

      final decryptedSecret = kem.decapsulate(
        encResult.ciphertext,
        keyPair.secretKey,
      );
      expect(decryptedSecret, equals(encResult.sharedSecret));

      kem.dispose();
    });

    test('Decapsulation with wrong secret key fails', () {
      final kem = KEM.create('ML-KEM-768');

      final keyPair1 = kem.generateKeyPair();
      final keyPair2 = kem.generateKeyPair();

      final encResult = kem.encapsulate(keyPair1.publicKey);

      // Decapsulate with wrong secret key - should produce different shared secret
      final wrongSecret = kem.decapsulate(
        encResult.ciphertext,
        keyPair2.secretKey,
      );
      expect(wrongSecret, isNot(equals(encResult.sharedSecret)));

      kem.dispose();
    });

    test('Different encapsulations produce different shared secrets', () {
      final kem = KEM.create('ML-KEM-768');

      final keyPair = kem.generateKeyPair();

      final encResult1 = kem.encapsulate(keyPair.publicKey);
      final encResult2 = kem.encapsulate(keyPair.publicKey);

      // Each encapsulation should produce different ciphertext and shared secret
      expect(encResult1.ciphertext, isNot(equals(encResult2.ciphertext)));
      expect(encResult1.sharedSecret, isNot(equals(encResult2.sharedSecret)));

      // But both should decapsulate correctly
      final secret1 = kem.decapsulate(encResult1.ciphertext, keyPair.secretKey);
      final secret2 = kem.decapsulate(encResult2.ciphertext, keyPair.secretKey);

      expect(secret1, equals(encResult1.sharedSecret));
      expect(secret2, equals(encResult2.sharedSecret));

      kem.dispose();
    });
  });

  group('KEM Deterministic Key Generation', () {
    test('ML-KEM-768 supports deterministic generation', () {
      final kem = KEM.create('ML-KEM-768');

      expect(kem.supportsDeterministicGeneration, isTrue);
      expect(kem.seedLength, equals(64));

      kem.dispose();
    });

    test('Same seed produces identical keys', () {
      final kem = KEM.create('ML-KEM-768');

      if (!kem.supportsDeterministicGeneration) {
        kem.dispose();
        return;
      }

      final seed = Uint8List.fromList(
        List.generate(kem.seedLength!, (i) => i % 256),
      );

      final keyPair1 = kem.generateKeyPairDerand(seed);
      final keyPair2 = kem.generateKeyPairDerand(seed);

      expect(keyPair1.publicKey, equals(keyPair2.publicKey));
      expect(keyPair1.secretKey, equals(keyPair2.secretKey));

      kem.dispose();
    });

    test('Different seeds produce different keys', () {
      final kem = KEM.create('ML-KEM-768');

      if (!kem.supportsDeterministicGeneration) {
        kem.dispose();
        return;
      }

      final seed1 = Uint8List.fromList(
        List.generate(kem.seedLength!, (i) => i % 256),
      );
      final seed2 = Uint8List.fromList(
        List.generate(kem.seedLength!, (i) => (i + 1) % 256),
      );

      final keyPair1 = kem.generateKeyPairDerand(seed1);
      final keyPair2 = kem.generateKeyPairDerand(seed2);

      expect(keyPair1.publicKey, isNot(equals(keyPair2.publicKey)));
      expect(keyPair1.secretKey, isNot(equals(keyPair2.secretKey)));

      kem.dispose();
    });

    test('Invalid seed length throws exception', () {
      final kem = KEM.create('ML-KEM-768');

      if (!kem.supportsDeterministicGeneration) {
        kem.dispose();
        return;
      }

      final invalidSeed = Uint8List(10); // Wrong size

      expect(
        () => kem.generateKeyPairDerand(invalidSeed),
        throwsA(isA<LibOQSException>()),
      );

      kem.dispose();
    });

    test('Deterministic keys work for encapsulation/decapsulation', () {
      final kem = KEM.create('ML-KEM-768');

      if (!kem.supportsDeterministicGeneration) {
        kem.dispose();
        return;
      }

      final seed = Uint8List.fromList(
        List.generate(kem.seedLength!, (i) => (i * 7 + 13) % 256),
      );

      final keyPair = kem.generateKeyPairDerand(seed);

      final encResult = kem.encapsulate(keyPair.publicKey);
      final sharedSecret = kem.decapsulate(
        encResult.ciphertext,
        keyPair.secretKey,
      );

      expect(sharedSecret, equals(encResult.sharedSecret));

      kem.dispose();
    });

    test('All ML-KEM variants support deterministic generation', () {
      final algorithms = ['ML-KEM-512', 'ML-KEM-768', 'ML-KEM-1024'];

      for (final algName in algorithms) {
        final kem = KEM.create(algName);
        expect(
          kem.supportsDeterministicGeneration,
          isTrue,
          reason: '$algName should support deterministic generation',
        );
        expect(
          kem.seedLength,
          equals(64),
          reason: '$algName seed length should be 64',
        );
        kem.dispose();
      }
    });

    test('Kyber variants do not support deterministic generation', () {
      final algorithms = ['Kyber512', 'Kyber768', 'Kyber1024'];

      for (final algName in algorithms) {
        if (!KEM.isSupported(algName)) continue;

        final kem = KEM.create(algName);
        expect(
          kem.supportsDeterministicGeneration,
          isFalse,
          reason: '$algName should not support deterministic generation',
        );
        expect(
          kem.seedLength,
          isNull,
          reason: '$algName seed length should be null',
        );

        // Verify that calling generateKeyPairDerand throws
        expect(
          () => kem.generateKeyPairDerand(Uint8List(32)),
          throwsA(isA<LibOQSException>()),
        );

        kem.dispose();
      }
    });
  });

  group('KEM Algorithm Enumeration', () {
    test('All supported KEM algorithms can be instantiated', () {
      final algorithms = LibOQS.getSupportedKEMAlgorithms();
      expect(algorithms.isNotEmpty, isTrue);

      int successCount = 0;

      for (final alg in algorithms) {
        try {
          final kem = KEM.create(alg);
          expect(kem.publicKeyLength, greaterThan(0));
          expect(kem.secretKeyLength, greaterThan(0));
          expect(kem.ciphertextLength, greaterThan(0));
          expect(kem.sharedSecretLength, greaterThan(0));
          kem.dispose();
          successCount++;
        } catch (e) {
          // Algorithm not supported in this build
        }
      }

      print('KEM algorithms: $successCount available');
      expect(successCount, greaterThan(0));
    });
  });

  group('KEM Edge Cases', () {
    test('Multiple key pairs from same KEM instance', () {
      final kem = KEM.create('ML-KEM-768');

      final keyPair1 = kem.generateKeyPair();
      final keyPair2 = kem.generateKeyPair();
      final keyPair3 = kem.generateKeyPair();

      // All key pairs should be different
      expect(keyPair1.publicKey, isNot(equals(keyPair2.publicKey)));
      expect(keyPair2.publicKey, isNot(equals(keyPair3.publicKey)));
      expect(keyPair1.publicKey, isNot(equals(keyPair3.publicKey)));

      // All should work for encapsulation
      for (final keyPair in [keyPair1, keyPair2, keyPair3]) {
        final encResult = kem.encapsulate(keyPair.publicKey);
        final secret = kem.decapsulate(encResult.ciphertext, keyPair.secretKey);
        expect(secret, equals(encResult.sharedSecret));
      }

      kem.dispose();
    });

    test('Invalid public key length throws exception', () {
      final kem = KEM.create('ML-KEM-768');

      final invalidPublicKey = Uint8List(100); // Wrong size

      expect(
        () => kem.encapsulate(invalidPublicKey),
        throwsA(isA<LibOQSException>()),
      );

      kem.dispose();
    });

    test('Invalid secret key length throws exception', () {
      final kem = KEM.create('ML-KEM-768');

      final keyPair = kem.generateKeyPair();
      final encResult = kem.encapsulate(keyPair.publicKey);

      final invalidSecretKey = Uint8List(100); // Wrong size

      expect(
        () => kem.decapsulate(encResult.ciphertext, invalidSecretKey),
        throwsA(isA<LibOQSException>()),
      );

      kem.dispose();
    });

    test('Invalid ciphertext length throws exception', () {
      final kem = KEM.create('ML-KEM-768');

      final keyPair = kem.generateKeyPair();
      final invalidCiphertext = Uint8List(100); // Wrong size

      expect(
        () => kem.decapsulate(invalidCiphertext, keyPair.secretKey),
        throwsA(isA<LibOQSException>()),
      );

      kem.dispose();
    });

    test('Unsupported algorithm throws exception', () {
      expect(
        () => KEM.create('NonExistentAlgorithm'),
        throwsA(isA<LibOQSException>()),
      );
    });
  });

  group('KEM Property Getters', () {
    test('algorithmVersion returns valid string', () {
      final kem = KEM.create('ML-KEM-768');
      try {
        final version = kem.algorithmVersion;
        expect(version, isNotEmpty);
        expect(version, isA<String>());
        print('ML-KEM-768 algorithm version: $version');
      } finally {
        kem.dispose();
      }
    });

    test('claimedNistLevel returns valid level', () {
      final kem = KEM.create('ML-KEM-768');
      try {
        final level = kem.claimedNistLevel;
        expect(level, greaterThan(0));
        expect(level, lessThanOrEqualTo(5));
        print('ML-KEM-768 NIST level: $level');
      } finally {
        kem.dispose();
      }
    });

    test('isIndCcaSecure returns boolean', () {
      final kem = KEM.create('ML-KEM-768');
      try {
        final secure = kem.isIndCcaSecure;
        expect(secure, isA<bool>());
        print('ML-KEM-768 IND-CCA secure: $secure');
      } finally {
        kem.dispose();
      }
    });

    test('property getters throw after dispose', () {
      final kem = KEM.create('ML-KEM-768');
      kem.dispose();

      expect(() => kem.algorithmVersion, throwsStateError);
      expect(() => kem.claimedNistLevel, throwsStateError);
      expect(() => kem.isIndCcaSecure, throwsStateError);
      expect(() => kem.seedLength, throwsStateError);
      expect(() => kem.supportsDeterministicGeneration, throwsStateError);
      expect(() => kem.publicKeyLength, throwsStateError);
      expect(() => kem.secretKeyLength, throwsStateError);
      expect(() => kem.ciphertextLength, throwsStateError);
      expect(() => kem.sharedSecretLength, throwsStateError);
    });

    test('all ML-KEM variants have correct NIST levels', () {
      final levels = {
        'ML-KEM-512': 1,
        'ML-KEM-768': 3,
        'ML-KEM-1024': 5,
      };

      for (final entry in levels.entries) {
        final kem = KEM.create(entry.key);
        try {
          expect(
            kem.claimedNistLevel,
            equals(entry.value),
            reason: '${entry.key} should have NIST level ${entry.value}',
          );
        } finally {
          kem.dispose();
        }
      }
    });
  });

  group('KEMKeyPair Serialization', () {
    test('toStrings returns base64 encoded keys', () {
      final kem = KEM.create('ML-KEM-768');
      try {
        final keyPair = kem.generateKeyPair();
        final strings = keyPair.toStrings();

        expect(strings.containsKey('publicKey'), isTrue);
        expect(strings.containsKey('secretKey'), isTrue);
        expect(strings['publicKey'], isNotEmpty);
        expect(strings['secretKey'], isNotEmpty);

        // Verify base64 decoding works
        final decodedPublic = base64Decode(strings['publicKey']!);
        final decodedSecret = base64Decode(strings['secretKey']!);

        expect(decodedPublic, equals(keyPair.publicKey));
        expect(decodedSecret, equals(keyPair.secretKey));

        keyPair.clearSecrets();
      } finally {
        kem.dispose();
      }
    });

    test('toHexStrings returns hex encoded keys', () {
      final kem = KEM.create('ML-KEM-768');
      try {
        final keyPair = kem.generateKeyPair();
        final hexStrings = keyPair.toHexStrings();

        expect(hexStrings.containsKey('publicKey'), isTrue);
        expect(hexStrings.containsKey('secretKey'), isTrue);

        // Hex string length should be double the byte length
        expect(
          hexStrings['publicKey']!.length,
          equals(keyPair.publicKey.length * 2),
        );
        expect(
          hexStrings['secretKey']!.length,
          equals(keyPair.secretKey.length * 2),
        );

        // Verify it contains only hex characters
        expect(
          RegExp(r'^[0-9a-f]+$').hasMatch(hexStrings['publicKey']!),
          isTrue,
        );
        expect(
          RegExp(r'^[0-9a-f]+$').hasMatch(hexStrings['secretKey']!),
          isTrue,
        );

        keyPair.clearSecrets();
      } finally {
        kem.dispose();
      }
    });

    test('publicKeyBase64 and publicKeyHex work correctly', () {
      final kem = KEM.create('ML-KEM-768');
      try {
        final keyPair = kem.generateKeyPair();

        // Test base64
        final base64Key = keyPair.publicKeyBase64;
        expect(base64Decode(base64Key), equals(keyPair.publicKey));

        // Test hex
        final hexKey = keyPair.publicKeyHex;
        expect(hexKey.length, equals(keyPair.publicKey.length * 2));
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(hexKey), isTrue);

        keyPair.clearSecrets();
      } finally {
        kem.dispose();
      }
    });
  });

  group('KEMEncapsulationResult Serialization', () {
    test('toStrings returns base64 encoded values', () {
      final kem = KEM.create('ML-KEM-768');
      try {
        final keyPair = kem.generateKeyPair();
        final encResult = kem.encapsulate(keyPair.publicKey);
        final strings = encResult.toStrings();

        expect(strings.containsKey('ciphertext'), isTrue);
        expect(strings.containsKey('sharedSecret'), isTrue);
        expect(strings['ciphertext'], isNotEmpty);
        expect(strings['sharedSecret'], isNotEmpty);

        // Verify base64 decoding works
        final decodedCiphertext = base64Decode(strings['ciphertext']!);
        final decodedSecret = base64Decode(strings['sharedSecret']!);

        expect(decodedCiphertext, equals(encResult.ciphertext));
        expect(decodedSecret, equals(encResult.sharedSecret));

        keyPair.clearSecrets();
        encResult.clearSecrets();
      } finally {
        kem.dispose();
      }
    });

    test('toHexStrings returns hex encoded values', () {
      final kem = KEM.create('ML-KEM-768');
      try {
        final keyPair = kem.generateKeyPair();
        final encResult = kem.encapsulate(keyPair.publicKey);
        final hexStrings = encResult.toHexStrings();

        expect(hexStrings.containsKey('ciphertext'), isTrue);
        expect(hexStrings.containsKey('sharedSecret'), isTrue);

        // Hex string length should be double the byte length
        expect(
          hexStrings['ciphertext']!.length,
          equals(encResult.ciphertext.length * 2),
        );
        expect(
          hexStrings['sharedSecret']!.length,
          equals(encResult.sharedSecret.length * 2),
        );

        // Verify it contains only hex characters
        expect(
          RegExp(r'^[0-9a-f]+$').hasMatch(hexStrings['ciphertext']!),
          isTrue,
        );
        expect(
          RegExp(r'^[0-9a-f]+$').hasMatch(hexStrings['sharedSecret']!),
          isTrue,
        );

        keyPair.clearSecrets();
        encResult.clearSecrets();
      } finally {
        kem.dispose();
      }
    });

    test('ciphertextBase64 and ciphertextHex work correctly', () {
      final kem = KEM.create('ML-KEM-768');
      try {
        final keyPair = kem.generateKeyPair();
        final encResult = kem.encapsulate(keyPair.publicKey);

        // Test base64
        final base64Ct = encResult.ciphertextBase64;
        expect(base64Decode(base64Ct), equals(encResult.ciphertext));

        // Test hex
        final hexCt = encResult.ciphertextHex;
        expect(hexCt.length, equals(encResult.ciphertext.length * 2));
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(hexCt), isTrue);

        keyPair.clearSecrets();
        encResult.clearSecrets();
      } finally {
        kem.dispose();
      }
    });
  });
}
