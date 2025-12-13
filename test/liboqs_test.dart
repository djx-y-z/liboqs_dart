import 'package:liboqs/liboqs.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    LibOQS.init();
  });

  tearDownAll(() {
    LibOQS.cleanup();
  });

  group('LibOQS Initialization', () {
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
}
