import 'package:liboqs/liboqs.dart';
import 'package:test/test.dart';

void main() {
  group('LibOQSException', () {
    test('toString with message only', () {
      final e = LibOQSException('Test error');
      expect(e.toString(), equals('LibOQSException: Test error'));
      expect(e.message, equals('Test error'));
      expect(e.errorCode, isNull);
      expect(e.algorithmName, isNull);
      expect(e.stackTrace, isNotNull);
    });

    test('toString with message and errorCode', () {
      final e = LibOQSException('Test error', 42);
      expect(e.toString(), equals('LibOQSException(code: 42): Test error'));
      expect(e.errorCode, equals(42));
      expect(e.algorithmName, isNull);
    });

    test('toString with message, errorCode, and algorithmName', () {
      final e = LibOQSException('Test error', 42, 'ML-KEM-768');
      expect(
        e.toString(),
        equals('LibOQSException(code: 42)[alg: ML-KEM-768]: Test error'),
      );
      expect(e.errorCode, equals(42));
      expect(e.algorithmName, equals('ML-KEM-768'));
    });

    test('toString with message and algorithmName (no errorCode)', () {
      final e = LibOQSException('Test error', null, 'ML-KEM-768');
      expect(
        e.toString(),
        equals('LibOQSException[alg: ML-KEM-768]: Test error'),
      );
      expect(e.errorCode, isNull);
      expect(e.algorithmName, equals('ML-KEM-768'));
    });

    test('toString with zero errorCode', () {
      final e = LibOQSException('Test error', 0);
      expect(e.toString(), equals('LibOQSException(code: 0): Test error'));
      expect(e.errorCode, equals(0));
    });

    test('toString with negative errorCode', () {
      final e = LibOQSException('Test error', -1);
      expect(e.toString(), equals('LibOQSException(code: -1): Test error'));
      expect(e.errorCode, equals(-1));
    });

    test('stackTrace is captured at creation time', () {
      final e = LibOQSException('Test');
      expect(e.stackTrace, isNotNull);
      expect(e.stackTrace.toString(), contains('exception_test.dart'));
    });
  });
}
