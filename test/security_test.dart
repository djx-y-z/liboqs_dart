// Security-focused tests for liboqs_dart
//
// These tests verify security-critical functionality:
// - Memory zeroing (clearSecrets)
// - Constant-time comparison
// - Disposed state protection
// - Safe serialization methods

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

  group('Memory Zeroing (clearSecrets)', () {
    test('KEMKeyPair.clearSecrets() zeros secret key', () {
      final kem = KEM.create('ML-KEM-768');

      try {
        final keyPair = kem.generateKeyPair();

        // Verify secret key is not all zeros before clearing
        final hasNonZero = keyPair.secretKey.any((byte) => byte != 0);
        expect(
          hasNonZero,
          isTrue,
          reason: 'Secret key should not be all zeros initially',
        );

        // Store original length
        final originalLength = keyPair.secretKey.length;

        // Clear secrets
        keyPair.clearSecrets();

        // Verify secret key is now all zeros
        final allZeros = keyPair.secretKey.every((byte) => byte == 0);
        expect(
          allZeros,
          isTrue,
          reason: 'Secret key should be all zeros after clearSecrets()',
        );

        // Length should remain the same
        expect(keyPair.secretKey.length, equals(originalLength));
      } finally {
        kem.dispose();
      }
    });

    test('KEMEncapsulationResult.clearSecrets() zeros shared secret', () {
      final kem = KEM.create('ML-KEM-768');

      try {
        final keyPair = kem.generateKeyPair();
        final encResult = kem.encapsulate(keyPair.publicKey);

        // Verify shared secret is not all zeros before clearing
        final hasNonZero = encResult.sharedSecret.any((byte) => byte != 0);
        expect(
          hasNonZero,
          isTrue,
          reason: 'Shared secret should not be all zeros initially',
        );

        // Store original length
        final originalLength = encResult.sharedSecret.length;

        // Clear secrets
        encResult.clearSecrets();

        // Verify shared secret is now all zeros
        final allZeros = encResult.sharedSecret.every((byte) => byte == 0);
        expect(
          allZeros,
          isTrue,
          reason: 'Shared secret should be all zeros after clearSecrets()',
        );

        // Length should remain the same
        expect(encResult.sharedSecret.length, equals(originalLength));

        // Cleanup
        keyPair.clearSecrets();
      } finally {
        kem.dispose();
      }
    });

    test('SignatureKeyPair.clearSecrets() zeros secret key', () {
      final sig = Signature.create('ML-DSA-65');

      try {
        final keyPair = sig.generateKeyPair();

        // Verify secret key is not all zeros before clearing
        final hasNonZero = keyPair.secretKey.any((byte) => byte != 0);
        expect(
          hasNonZero,
          isTrue,
          reason: 'Secret key should not be all zeros initially',
        );

        // Store original length
        final originalLength = keyPair.secretKey.length;

        // Clear secrets
        keyPair.clearSecrets();

        // Verify secret key is now all zeros
        final allZeros = keyPair.secretKey.every((byte) => byte == 0);
        expect(
          allZeros,
          isTrue,
          reason: 'Secret key should be all zeros after clearSecrets()',
        );

        // Length should remain the same
        expect(keyPair.secretKey.length, equals(originalLength));
      } finally {
        sig.dispose();
      }
    });
  });

  group('Constant-Time Comparison', () {
    test('constantTimeEquals returns true for equal arrays', () {
      final a = Uint8List.fromList([1, 2, 3, 4, 5]);
      final b = Uint8List.fromList([1, 2, 3, 4, 5]);

      expect(LibOQSUtils.constantTimeEquals(a, b), isTrue);
    });

    test('constantTimeEquals returns false for different arrays', () {
      final a = Uint8List.fromList([1, 2, 3, 4, 5]);
      final b = Uint8List.fromList([1, 2, 3, 4, 6]);

      expect(LibOQSUtils.constantTimeEquals(a, b), isFalse);
    });

    test('constantTimeEquals returns false for different lengths', () {
      final a = Uint8List.fromList([1, 2, 3, 4, 5]);
      final b = Uint8List.fromList([1, 2, 3, 4]);

      expect(LibOQSUtils.constantTimeEquals(a, b), isFalse);
    });

    test('constantTimeEquals returns true for two empty arrays', () {
      final a = Uint8List(0);
      final b = Uint8List(0);

      expect(LibOQSUtils.constantTimeEquals(a, b), isTrue);
    });

    test('constantTimeEquals returns false when one array is empty', () {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List(0);

      expect(LibOQSUtils.constantTimeEquals(a, b), isFalse);
      expect(LibOQSUtils.constantTimeEquals(b, a), isFalse);
    });

    test('constantTimeEquals works with large arrays', () {
      final a = Uint8List(10000);
      final b = Uint8List(10000);

      // Fill with same pattern
      for (var i = 0; i < 10000; i++) {
        a[i] = i % 256;
        b[i] = i % 256;
      }

      expect(LibOQSUtils.constantTimeEquals(a, b), isTrue);

      // Change one byte
      b[5000] = (b[5000] + 1) % 256;
      expect(LibOQSUtils.constantTimeEquals(a, b), isFalse);
    });

    test('constantTimeEquals with real shared secrets', () {
      final kem = KEM.create('ML-KEM-768');

      try {
        final keyPair = kem.generateKeyPair();
        final enc1 = kem.encapsulate(keyPair.publicKey);
        final enc2 = kem.encapsulate(keyPair.publicKey);

        // Decapsulated secrets should match their respective encapsulated secrets
        final dec1 = kem.decapsulate(enc1.ciphertext, keyPair.secretKey);
        final dec2 = kem.decapsulate(enc2.ciphertext, keyPair.secretKey);

        expect(LibOQSUtils.constantTimeEquals(enc1.sharedSecret, dec1), isTrue);
        expect(LibOQSUtils.constantTimeEquals(enc2.sharedSecret, dec2), isTrue);

        // Different encapsulations should produce different secrets
        expect(
          LibOQSUtils.constantTimeEquals(enc1.sharedSecret, enc2.sharedSecret),
          isFalse,
        );

        // Cleanup
        keyPair.clearSecrets();
        enc1.clearSecrets();
        enc2.clearSecrets();
      } finally {
        kem.dispose();
      }
    });
  });

  group('Disposed State Protection', () {
    test('KEM throws StateError after dispose', () {
      final kem = KEM.create('ML-KEM-768');
      kem.dispose();

      expect(() => kem.generateKeyPair(), throwsStateError);
    });

    test('Signature throws StateError after dispose', () {
      final sig = Signature.create('ML-DSA-65');
      sig.dispose();

      expect(() => sig.generateKeyPair(), throwsStateError);
    });

    test('Double dispose is safe', () {
      final kem = KEM.create('ML-KEM-768');
      kem.dispose();

      // Second dispose should not throw
      expect(() => kem.dispose(), returnsNormally);
    });
  });

  group('Safe Serialization', () {
    test('KEMKeyPair provides safe public key getters', () {
      final kem = KEM.create('ML-KEM-768');

      try {
        final keyPair = kem.generateKeyPair();

        // These should work and return non-empty strings
        final base64 = keyPair.publicKeyBase64;
        final hex = keyPair.publicKeyHex;

        expect(base64.isNotEmpty, isTrue);
        expect(hex.isNotEmpty, isTrue);

        // Hex should be double the length of bytes
        expect(hex.length, equals(keyPair.publicKey.length * 2));

        keyPair.clearSecrets();
      } finally {
        kem.dispose();
      }
    });

    test('SignatureKeyPair provides safe public key getters', () {
      final sig = Signature.create('ML-DSA-65');

      try {
        final keyPair = sig.generateKeyPair();

        // These should work and return non-empty strings
        final base64 = keyPair.publicKeyBase64;
        final hex = keyPair.publicKeyHex;

        expect(base64.isNotEmpty, isTrue);
        expect(hex.isNotEmpty, isTrue);

        // Hex should be double the length of bytes
        expect(hex.length, equals(keyPair.publicKey.length * 2));

        keyPair.clearSecrets();
      } finally {
        sig.dispose();
      }
    });

    test('KEMEncapsulationResult provides safe ciphertext getters', () {
      final kem = KEM.create('ML-KEM-768');

      try {
        final keyPair = kem.generateKeyPair();
        final encResult = kem.encapsulate(keyPair.publicKey);

        // These should work and return non-empty strings
        final base64 = encResult.ciphertextBase64;
        final hex = encResult.ciphertextHex;

        expect(base64.isNotEmpty, isTrue);
        expect(hex.isNotEmpty, isTrue);

        // Hex should be double the length of bytes
        expect(hex.length, equals(encResult.ciphertext.length * 2));

        keyPair.clearSecrets();
        encResult.clearSecrets();
      } finally {
        kem.dispose();
      }
    });
  });

  group('Memory Zeroing Utility', () {
    test('LibOQSUtils.zeroMemory zeros data in place', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      // Verify not all zeros
      expect(data.any((b) => b != 0), isTrue);

      LibOQSUtils.zeroMemory(data);

      // Verify all zeros
      expect(data.every((b) => b == 0), isTrue);
    });

    test('LibOQSUtils.zeroMemory handles empty data', () {
      final data = Uint8List(0);

      // Should not throw
      expect(() => LibOQSUtils.zeroMemory(data), returnsNormally);
    });

    test('LibOQSUtils.zeroMemory handles large data', () {
      final data = Uint8List(100000);
      for (var i = 0; i < data.length; i++) {
        data[i] = i % 256;
      }

      LibOQSUtils.zeroMemory(data);

      expect(data.every((b) => b == 0), isTrue);
    });
  });
}
