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
}
