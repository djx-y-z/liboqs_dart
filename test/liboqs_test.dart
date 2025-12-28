import 'package:liboqs/liboqs.dart';
import 'package:liboqs/src/base.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    LibOQS.init();
  });

  tearDownAll(() {
    LibOQS.cleanup();
  });

  group('LibOQS Initialization', () {
    test('isInitialized returns true after init', () {
      expect(LibOQSBase.isInitialized, isTrue);
    });

    test('should return version information', () {
      final version = LibOQS.getVersion();
      expect(version, isNotEmpty);
      expect(version, contains('.'));
      print('LibOQS version: $version');
    });

    test('should list supported KEM algorithms', () {
      final kems = LibOQS.getSupportedKEMAlgorithms();
      expect(kems, isNotEmpty);
      // liboqs 0.15+ uses NIST standardized names
      expect(kems, contains('ML-KEM-768'));
      print('Supported KEMs: ${kems.length} algorithms');
    });

    test('should list supported signature algorithms', () {
      final sigs = LibOQS.getSupportedSignatureAlgorithms();
      expect(sigs, isNotEmpty);
      // liboqs 0.15+ uses NIST standardized names
      expect(sigs, contains('ML-DSA-65'));
      print('Supported Signatures: ${sigs.length} algorithms');
    });
  });

  group('LibOQS Algorithm Support Checks', () {
    test('isKEMSupported returns true for valid KEM algorithm', () {
      expect(LibOQS.isKEMSupported('ML-KEM-768'), isTrue);
      expect(LibOQS.isKEMSupported('ML-KEM-512'), isTrue);
      expect(LibOQS.isKEMSupported('ML-KEM-1024'), isTrue);
    });

    test('isKEMSupported returns false for invalid algorithm', () {
      expect(LibOQS.isKEMSupported('NonExistent-KEM'), isFalse);
      expect(LibOQS.isKEMSupported('InvalidAlgorithm'), isFalse);
    });

    test('isKEMSupported returns false for signature algorithm', () {
      expect(LibOQS.isKEMSupported('ML-DSA-65'), isFalse);
    });

    test('isSignatureSupported returns true for valid signature algorithm', () {
      expect(LibOQS.isSignatureSupported('ML-DSA-65'), isTrue);
      expect(LibOQS.isSignatureSupported('ML-DSA-44'), isTrue);
      expect(LibOQS.isSignatureSupported('ML-DSA-87'), isTrue);
    });

    test('isSignatureSupported returns false for invalid algorithm', () {
      expect(LibOQS.isSignatureSupported('NonExistent-Sig'), isFalse);
      expect(LibOQS.isSignatureSupported('InvalidAlgorithm'), isFalse);
    });

    test('isSignatureSupported returns false for KEM algorithm', () {
      expect(LibOQS.isSignatureSupported('ML-KEM-768'), isFalse);
    });
  });
}
