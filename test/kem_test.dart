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
}
