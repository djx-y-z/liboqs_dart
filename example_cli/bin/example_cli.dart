import 'dart:convert';
import 'dart:typed_data';

import 'package:liboqs/liboqs.dart';

void main() {
  print('=== liboqs CLI Example ===\n');
  print('liboqs version: ${LibOQS.getVersion()}');
  print('');

  _kemDemo();
  print('');
  _signatureDemo();
}

void _kemDemo() {
  print('--- KEM Demo (ML-KEM-768) ---');

  final kem = KEM.create('ML-KEM-768');

  try {
    // Generate key pair
    final keyPair = kem.generateKeyPair();
    print('[+] Generated key pair');
    print('    Public key: ${keyPair.publicKey.length} bytes');
    print('    Secret key: ${keyPair.secretKey.length} bytes');

    // Encapsulate
    final encResult = kem.encapsulate(keyPair.publicKey);
    print('[+] Encapsulated shared secret');
    print('    Ciphertext: ${encResult.ciphertext.length} bytes');

    // Decapsulate
    final sharedSecret = kem.decapsulate(
      encResult.ciphertext,
      keyPair.secretKey,
    );
    print('[+] Decapsulated shared secret');

    // Verify using constant-time comparison (prevents timing attacks)
    final match = LibOQSUtils.constantTimeEquals(
      encResult.sharedSecret,
      sharedSecret,
    );
    print('[+] Secrets match: $match');
  } finally {
    kem.dispose();
  }
}

void _signatureDemo() {
  print('--- Signature Demo (ML-DSA-65) ---');

  final sig = Signature.create('ML-DSA-65');

  try {
    // Generate key pair
    final keyPair = sig.generateKeyPair();
    print('[+] Generated key pair');

    // Sign message
    final message = Uint8List.fromList(
      utf8.encode('Hello, Post-Quantum World!'),
    );
    final signature = sig.sign(message, keyPair.secretKey);
    print('[+] Signed message (${signature.length} bytes)');

    // Verify
    final isValid = sig.verify(message, signature, keyPair.publicKey);
    print('[+] Signature valid: $isValid');

    // Test with wrong message
    final wrongMessage = Uint8List.fromList(utf8.encode('Wrong message'));
    final isInvalid = sig.verify(wrongMessage, signature, keyPair.publicKey);
    print('[+] Wrong message rejected: ${!isInvalid}');
  } finally {
    sig.dispose();
  }
}
