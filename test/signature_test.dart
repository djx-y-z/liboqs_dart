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

  group('Signature Operations', () {
    test('ML-DSA-44 key generation and signing', () {
      final sig = Signature.create('ML-DSA-44');

      final keyPair = sig.generateKeyPair();
      expect(keyPair.publicKey.length, equals(1312));
      expect(keyPair.secretKey.length, equals(2560));

      final message = Uint8List.fromList('Test message'.codeUnits);
      final signature = sig.sign(message, keyPair.secretKey);
      expect(signature.length, lessThanOrEqualTo(2420));

      final isValid = sig.verify(message, signature, keyPair.publicKey);
      expect(isValid, isTrue);

      sig.dispose();
    });

    test('ML-DSA-65 key generation and signing', () {
      final sig = Signature.create('ML-DSA-65');

      final keyPair = sig.generateKeyPair();
      expect(keyPair.publicKey.length, equals(1952));
      expect(keyPair.secretKey.length, equals(4032));

      final message = Uint8List.fromList(
        'Test message for ML-DSA-65'.codeUnits,
      );
      final signature = sig.sign(message, keyPair.secretKey);
      expect(signature.length, lessThanOrEqualTo(3309));

      final isValid = sig.verify(message, signature, keyPair.publicKey);
      expect(isValid, isTrue);

      sig.dispose();
    });

    test('ML-DSA-87 key generation and signing', () {
      final sig = Signature.create('ML-DSA-87');

      final keyPair = sig.generateKeyPair();
      expect(keyPair.publicKey.length, equals(2592));
      expect(keyPair.secretKey.length, equals(4896));

      final message = Uint8List.fromList(
        'Test message for ML-DSA-87'.codeUnits,
      );
      final signature = sig.sign(message, keyPair.secretKey);
      expect(signature.length, lessThanOrEqualTo(4627));

      final isValid = sig.verify(message, signature, keyPair.publicKey);
      expect(isValid, isTrue);

      sig.dispose();
    });

    test('Signature verification fails with wrong message', () {
      final sig = Signature.create('ML-DSA-65');

      final keyPair = sig.generateKeyPair();
      final message = Uint8List.fromList('Original message'.codeUnits);
      final signature = sig.sign(message, keyPair.secretKey);

      final wrongMessage = Uint8List.fromList('Wrong message'.codeUnits);
      final isValid = sig.verify(wrongMessage, signature, keyPair.publicKey);
      expect(isValid, isFalse);

      sig.dispose();
    });

    test('Signature verification fails with wrong public key', () {
      final sig = Signature.create('ML-DSA-65');

      final keyPair1 = sig.generateKeyPair();
      final keyPair2 = sig.generateKeyPair();

      final message = Uint8List.fromList('Test message'.codeUnits);
      final signature = sig.sign(message, keyPair1.secretKey);

      // Verify with wrong public key
      final isValid = sig.verify(message, signature, keyPair2.publicKey);
      expect(isValid, isFalse);

      sig.dispose();
    });

    test('Empty message throws ArgumentError', () {
      final sig = Signature.create('ML-DSA-65');

      final keyPair = sig.generateKeyPair();
      final emptyMessage = Uint8List(0);

      // Empty messages are not allowed
      expect(
        () => sig.sign(emptyMessage, keyPair.secretKey),
        throwsArgumentError,
      );

      sig.dispose();
    });

    test('Sign and verify large message', () {
      final sig = Signature.create('ML-DSA-65');

      final keyPair = sig.generateKeyPair();
      // 1MB message
      final largeMessage = Uint8List(1024 * 1024);
      for (int i = 0; i < largeMessage.length; i++) {
        largeMessage[i] = i % 256;
      }

      final signature = sig.sign(largeMessage, keyPair.secretKey);
      final isValid = sig.verify(largeMessage, signature, keyPair.publicKey);
      expect(isValid, isTrue);

      sig.dispose();
    });

    test('Falcon-512 key generation and signing', () {
      if (!Signature.isSupported('Falcon-512')) {
        print('Falcon-512 not available - skipping test');
        return;
      }

      final sig = Signature.create('Falcon-512');
      final keyPair = sig.generateKeyPair();
      expect(keyPair.publicKey.isNotEmpty, isTrue);
      expect(keyPair.secretKey.isNotEmpty, isTrue);

      final message = Uint8List.fromList('Falcon test'.codeUnits);
      final signature = sig.sign(message, keyPair.secretKey);

      final isValid = sig.verify(message, signature, keyPair.publicKey);
      expect(isValid, isTrue);

      sig.dispose();
    });
  });

  group('Signature Algorithm Enumeration', () {
    test('All supported signature algorithms can be instantiated', () {
      final algorithms = LibOQS.getSupportedSignatureAlgorithms();
      expect(algorithms.isNotEmpty, isTrue);

      int successCount = 0;

      for (final alg in algorithms) {
        try {
          final sig = Signature.create(alg);
          // Basic sanity check
          expect(sig.publicKeyLength, greaterThan(0));
          expect(sig.secretKeyLength, greaterThan(0));
          expect(sig.maxSignatureLength, greaterThan(0));
          sig.dispose();
          successCount++;
        } catch (e) {
          // Algorithm not supported in this build
        }
      }

      print('Signature algorithms: $successCount available');
      expect(successCount, greaterThan(0));
    });
  });

  group('Signature Property Getters', () {
    test('algorithmVersion returns valid string', () {
      final sig = Signature.create('ML-DSA-65');
      try {
        final version = sig.algorithmVersion;
        expect(version, isNotEmpty);
        expect(version, isA<String>());
        print('ML-DSA-65 algorithm version: $version');
      } finally {
        sig.dispose();
      }
    });

    test('claimedNistLevel returns valid level', () {
      final sig = Signature.create('ML-DSA-65');
      try {
        final level = sig.claimedNistLevel;
        expect(level, greaterThan(0));
        expect(level, lessThanOrEqualTo(5));
        print('ML-DSA-65 NIST level: $level');
      } finally {
        sig.dispose();
      }
    });

    test('isEufCmaSecure returns boolean', () {
      final sig = Signature.create('ML-DSA-65');
      try {
        final secure = sig.isEufCmaSecure;
        expect(secure, isA<bool>());
        print('ML-DSA-65 EUF-CMA secure: $secure');
      } finally {
        sig.dispose();
      }
    });

    test('property getters throw after dispose', () {
      final sig = Signature.create('ML-DSA-65');
      sig.dispose();

      expect(() => sig.algorithmVersion, throwsStateError);
      expect(() => sig.claimedNistLevel, throwsStateError);
      expect(() => sig.isEufCmaSecure, throwsStateError);
      expect(() => sig.publicKeyLength, throwsStateError);
      expect(() => sig.secretKeyLength, throwsStateError);
      expect(() => sig.maxSignatureLength, throwsStateError);
    });

    test('all ML-DSA variants have correct NIST levels', () {
      final levels = {
        'ML-DSA-44': 2,
        'ML-DSA-65': 3,
        'ML-DSA-87': 5,
      };

      for (final entry in levels.entries) {
        final sig = Signature.create(entry.key);
        try {
          expect(
            sig.claimedNistLevel,
            equals(entry.value),
            reason: '${entry.key} should have NIST level ${entry.value}',
          );
        } finally {
          sig.dispose();
        }
      }
    });
  });

  group('Signature Verification Edge Cases', () {
    test('verify throws for empty signature', () {
      final sig = Signature.create('ML-DSA-65');
      try {
        final keyPair = sig.generateKeyPair();
        final message = Uint8List.fromList('Test'.codeUnits);

        expect(
          () => sig.verify(message, Uint8List(0), keyPair.publicKey),
          throwsA(isA<LibOQSException>()),
        );

        keyPair.clearSecrets();
      } finally {
        sig.dispose();
      }
    });

    test('verify throws for signature exceeding max length', () {
      final sig = Signature.create('ML-DSA-65');
      try {
        final keyPair = sig.generateKeyPair();
        final message = Uint8List.fromList('Test'.codeUnits);
        final oversizedSig = Uint8List(sig.maxSignatureLength + 1);

        expect(
          () => sig.verify(message, oversizedSig, keyPair.publicKey),
          throwsA(isA<LibOQSException>()),
        );

        keyPair.clearSecrets();
      } finally {
        sig.dispose();
      }
    });

    test('verify throws for invalid public key length', () {
      final sig = Signature.create('ML-DSA-65');
      try {
        final keyPair = sig.generateKeyPair();
        final message = Uint8List.fromList('Test'.codeUnits);
        final signature = sig.sign(message, keyPair.secretKey);

        expect(
          () => sig.verify(message, signature, Uint8List(10)),
          throwsA(isA<LibOQSException>()),
        );

        keyPair.clearSecrets();
      } finally {
        sig.dispose();
      }
    });

    test('sign throws for invalid secret key length', () {
      final sig = Signature.create('ML-DSA-65');
      try {
        final message = Uint8List.fromList('Test'.codeUnits);

        expect(
          () => sig.sign(message, Uint8List(10)),
          throwsA(isA<LibOQSException>()),
        );
      } finally {
        sig.dispose();
      }
    });

    test('unsupported algorithm throws exception', () {
      expect(
        () => Signature.create('NonExistentAlgorithm'),
        throwsA(isA<LibOQSException>()),
      );
    });
  });

  group('SignatureKeyPair Serialization', () {
    test('toStrings returns base64 encoded keys', () {
      final sig = Signature.create('ML-DSA-65');
      try {
        final keyPair = sig.generateKeyPair();
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
        sig.dispose();
      }
    });

    test('toHexStrings returns hex encoded keys', () {
      final sig = Signature.create('ML-DSA-65');
      try {
        final keyPair = sig.generateKeyPair();
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
        sig.dispose();
      }
    });

    test('publicKeyBase64 and publicKeyHex work correctly', () {
      final sig = Signature.create('ML-DSA-65');
      try {
        final keyPair = sig.generateKeyPair();

        // Test base64
        final base64Key = keyPair.publicKeyBase64;
        expect(base64Decode(base64Key), equals(keyPair.publicKey));

        // Test hex
        final hexKey = keyPair.publicKeyHex;
        expect(hexKey.length, equals(keyPair.publicKey.length * 2));
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(hexKey), isTrue);

        keyPair.clearSecrets();
      } finally {
        sig.dispose();
      }
    });
  });
}
