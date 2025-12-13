import 'package:liboqs/liboqs.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    LibOQS.init();
  });

  tearDownAll(() {
    LibOQS.cleanup();
  });

  group('OQSRandom', () {
    test('generateBytes returns correct length', () {
      final bytes16 = OQSRandom.generateBytes(16);
      expect(bytes16.length, equals(16));

      final bytes32 = OQSRandom.generateBytes(32);
      expect(bytes32.length, equals(32));

      final bytes64 = OQSRandom.generateBytes(64);
      expect(bytes64.length, equals(64));
    });

    test('generateBytes returns different values each time', () {
      final bytes1 = OQSRandom.generateBytes(32);
      final bytes2 = OQSRandom.generateBytes(32);
      final bytes3 = OQSRandom.generateBytes(32);

      // All three should be different
      expect(bytes1, isNot(equals(bytes2)));
      expect(bytes2, isNot(equals(bytes3)));
      expect(bytes1, isNot(equals(bytes3)));
    });

    test('generateBytes throws on invalid length', () {
      expect(() => OQSRandom.generateBytes(0), throwsArgumentError);
      expect(() => OQSRandom.generateBytes(-1), throwsArgumentError);
      expect(
        () => OQSRandom.generateBytes(1024 * 1024 + 1),
        throwsArgumentError,
      );
    });

    test('generateSeed returns correct length', () {
      final seed16 = OQSRandom.generateSeed(16);
      expect(seed16.length, equals(16));

      final seed32 = OQSRandom.generateSeed(); // default 32
      expect(seed32.length, equals(32));

      final seed64 = OQSRandom.generateSeed(64);
      expect(seed64.length, equals(64));
    });

    test('generateSeed throws on invalid length', () {
      expect(() => OQSRandom.generateSeed(15), throwsArgumentError);
      expect(() => OQSRandom.generateSeed(65), throwsArgumentError);
    });

    test('generateInt returns value in range', () {
      for (int i = 0; i < 100; i++) {
        final value = OQSRandom.generateInt(0, 100);
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThan(100));
      }
    });

    test('generateInt respects min and max', () {
      for (int i = 0; i < 100; i++) {
        final value = OQSRandom.generateInt(50, 60);
        expect(value, greaterThanOrEqualTo(50));
        expect(value, lessThan(60));
      }
    });

    test('generateInt throws on invalid range', () {
      expect(() => OQSRandom.generateInt(10, 10), throwsArgumentError);
      expect(() => OQSRandom.generateInt(10, 5), throwsArgumentError);
    });

    test('getAvailableAlgorithms returns non-empty list', () {
      final algorithms = OQSRandom.getAvailableAlgorithms();
      expect(algorithms.isNotEmpty, isTrue);
      expect(algorithms.contains('system'), isTrue);
    });

    test('resetToDefault succeeds', () {
      final result = OQSRandom.resetToDefault();
      expect(result, isTrue);
    });

    test('generate large random data (1KB)', () {
      final bytes = OQSRandom.generateBytes(1024);
      expect(bytes.length, equals(1024));

      // Verify it's not all zeros (extremely unlikely for real random data)
      final sum = bytes.fold<int>(0, (a, b) => a + b);
      expect(sum, greaterThan(0));
    });
  });

  group('OQSRandom extended methods', () {
    test('generateBool returns boolean values', () {
      int trueCount = 0;
      int falseCount = 0;

      for (int i = 0; i < 100; i++) {
        if (OQSRandom.generateBool()) {
          trueCount++;
        } else {
          falseCount++;
        }
      }

      // Both should have some occurrences (probability of all same is tiny)
      expect(trueCount, greaterThan(0));
      expect(falseCount, greaterThan(0));
    });

    test('generateDouble returns values in [0, 1)', () {
      for (int i = 0; i < 100; i++) {
        final value = OQSRandom.generateDouble();
        expect(value, greaterThanOrEqualTo(0.0));
        expect(value, lessThan(1.0));
      }
    });

    test('shuffleList randomizes list order', () {
      final original = List.generate(10, (i) => i);
      final shuffled = List.from(original);
      OQSRandom.shuffleList(shuffled);

      // List should have same elements
      expect(shuffled.toSet(), equals(original.toSet()));

      // Order should be different (probability of same order is 1/10!)
      expect(shuffled, isNot(equals(original)));
    });
  });
}
