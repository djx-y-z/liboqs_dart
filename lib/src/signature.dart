import 'dart:convert';
import 'dart:ffi';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'base.dart';
import 'bindings/liboqs_bindings.dart' as oqs;
import 'exception.dart';
import 'utils.dart';

final Finalizer<Pointer<oqs.OQS_SIG>> _sigFinalizer = Finalizer(
  (ptr) => oqs.OQS_SIG_free(ptr),
);

/// Digital Signature implementation
class Signature {
  late final Pointer<oqs.OQS_SIG> _sigPtr;
  final String algorithmName;

  bool _disposed = false;

  Signature._(this._sigPtr, this.algorithmName) {
    _sigFinalizer.attach(this, _sigPtr, detach: this);
  }
  void _checkDisposed() {
    if (_disposed) {
      throw StateError('Signature instance has been disposed');
    }
  }

  String get algorithmVersion {
    _checkDisposed();
    return _sigPtr.ref.alg_version.cast<Utf8>().toDartString();
  }

  int get claimedNistLevel {
    _checkDisposed();
    return _sigPtr.ref.claimed_nist_level;
  }

  bool get isEufCmaSecure {
    _checkDisposed();
    return _sigPtr.ref.euf_cma;
  }

  /// returns list of supported Signature algorithms from liboqs
  static List<String> getSupportedSignatureAlgorithms() {
    final sigCount = oqs.OQS_SIG_alg_count();
    final List<String> supportedSigs = [];

    for (int i = 0; i < sigCount; i++) {
      final sigNamePtr = oqs.OQS_SIG_alg_identifier(i);
      if (sigNamePtr != ffi.nullptr) {
        final sigName = sigNamePtr.cast<Utf8>().toDartString();
        // Store pointer to avoid memory leak
        final namePtr = sigName.toNativeUtf8();
        try {
          final isEnabled = oqs.OQS_SIG_alg_is_enabled(
            namePtr.cast<ffi.Char>(),
          );
          if (isEnabled == 1) {
            supportedSigs.add(sigName);
          }
        } finally {
          calloc.free(namePtr);
        }
      }
    }

    return supportedSigs;
  }

  /// Create a new Signature instance with the specified algorithm
  static Signature create(String algorithmName) {
    LibOQSBase.init(); // Ensure LibOQS is initialized
    LibOQSUtils.validateAlgorithmName(algorithmName);

    final namePtr = algorithmName.toNativeUtf8();
    try {
      final sigPtr = oqs.OQS_SIG_new(namePtr.cast());
      if (sigPtr == nullptr) {
        throw LibOQSException(
          'Failed to create Signature instance. Algorithm may not be supported or enabled.',
          null,
          algorithmName,
        );
      }
      return Signature._(sigPtr.cast<oqs.OQS_SIG>(), algorithmName);
    } finally {
      LibOQSUtils.freePointer(namePtr);
    }
  }

  /// Check if a signature algorithm is supported
  static bool isSupported(String algorithmName) {
    final namePtr = algorithmName.toNativeUtf8();
    try {
      return oqs.OQS_SIG_alg_is_enabled(namePtr.cast()) == 1;
    } finally {
      LibOQSUtils.freePointer(namePtr);
    }
  }

  /// Get the public key length for this signature algorithm
  int get publicKeyLength {
    _checkDisposed();
    return _sigPtr.ref.length_public_key;
  }

  /// Get the secret key length for this signature algorithm
  int get secretKeyLength {
    _checkDisposed();
    return _sigPtr.ref.length_secret_key;
  }

  /// Get the maximum signature length for this algorithm
  int get maxSignatureLength {
    _checkDisposed();
    return _sigPtr.ref.length_signature;
  }

  /// Generate a key pair
  SignatureKeyPair generateKeyPair() {
    _checkDisposed();
    final publicKey = LibOQSUtils.allocateBytes(publicKeyLength);
    final secretKey = LibOQSUtils.allocateBytes(secretKeyLength);

    try {
      // Call the keypair function pointer from the struct
      final keypairFn = _sigPtr.ref.keypair
          .asFunction<
            int Function(Pointer<Uint8> publicKey, Pointer<Uint8> secretKey)
          >();

      final result = keypairFn(publicKey, secretKey);
      if (result != 0) {
        throw LibOQSException('Failed to generate key pair', result);
      }

      return SignatureKeyPair(
        publicKey: LibOQSUtils.pointerToUint8List(publicKey, publicKeyLength),
        secretKey: LibOQSUtils.pointerToUint8List(secretKey, secretKeyLength),
      );
    } finally {
      LibOQSUtils.freePointer(publicKey);
      // Secure free for sensitive data
      LibOQSUtils.secureFreePointer(secretKey, secretKeyLength);
    }
  }

  /// Sign a message
  Uint8List sign(Uint8List message, Uint8List secretKey) {
    _checkDisposed();
    if (secretKey.length != secretKeyLength) {
      throw LibOQSException(
        'Invalid secret key length: expected $secretKeyLength, got ${secretKey.length}',
      );
    }

    final signature = LibOQSUtils.allocateBytes(maxSignatureLength);
    final signatureLength = calloc<Size>();
    signatureLength.value = maxSignatureLength;

    final messagePtr = LibOQSUtils.uint8ListToPointer(message);
    final secretKeyPtr = LibOQSUtils.uint8ListToPointer(secretKey);

    try {
      // Call the sign function pointer from the struct
      final signFn = _sigPtr.ref.sign
          .asFunction<
            int Function(
              Pointer<Uint8> signature,
              Pointer<Size> signatureLen,
              Pointer<Uint8> message,
              int messageLen,
              Pointer<Uint8> secretKey,
            )
          >();

      final result = signFn(
        signature,
        signatureLength,
        messagePtr,
        message.length,
        secretKeyPtr,
      );

      if (result != 0) {
        throw LibOQSException('Failed to sign message', result);
      }

      final actualLength = signatureLength.value;
      return LibOQSUtils.pointerToUint8List(signature, actualLength);
    } finally {
      LibOQSUtils.freePointer(signature);
      LibOQSUtils.freePointer(signatureLength.cast());
      LibOQSUtils.freePointer(messagePtr);
      // Secure free for sensitive data
      LibOQSUtils.secureFreePointer(secretKeyPtr, secretKey.length);
    }
  }

  /// Verify a signature
  bool verify(Uint8List message, Uint8List signature, Uint8List publicKey) {
    _checkDisposed();
    if (publicKey.length != publicKeyLength) {
      throw LibOQSException(
        'Invalid public key length: expected $publicKeyLength, got ${publicKey.length}',
      );
    }

    final messagePtr = LibOQSUtils.uint8ListToPointer(message);
    final signaturePtr = LibOQSUtils.uint8ListToPointer(signature);
    final publicKeyPtr = LibOQSUtils.uint8ListToPointer(publicKey);

    try {
      // Call the verify function pointer from the struct
      final verifyFn = _sigPtr.ref.verify
          .asFunction<
            int Function(
              Pointer<Uint8> message,
              int messageLen,
              Pointer<Uint8> signature,
              int signatureLen,
              Pointer<Uint8> publicKey,
            )
          >();

      final result = verifyFn(
        messagePtr,
        message.length,
        signaturePtr,
        signature.length,
        publicKeyPtr,
      );

      return result == 0;
    } finally {
      LibOQSUtils.freePointer(messagePtr);
      LibOQSUtils.freePointer(signaturePtr);
      LibOQSUtils.freePointer(publicKeyPtr);
    }
  }

  /// Clean up resources
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      _sigFinalizer.detach(this);
      oqs.OQS_SIG_free(_sigPtr);
    }
  }
}

/// Signature key pair
class SignatureKeyPair {
  final Uint8List publicKey;
  final Uint8List secretKey;

  const SignatureKeyPair({required this.publicKey, required this.secretKey});

  /// Returns all Uint8List properties as base64 encoded strings
  Map<String, String> toStrings() {
    return {
      'publicKey': base64Encode(publicKey),
      'secretKey': base64Encode(secretKey),
    };
  }

  /// Alternative method that returns properties as hex strings
  Map<String, String> toHexStrings() {
    return {
      'publicKey': publicKey
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      'secretKey': secretKey
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
    };
  }
}
