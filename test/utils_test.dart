import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:liboqs/liboqs.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    LibOQS.init();
  });

  tearDownAll(() {
    LibOQS.cleanup();
  });

  group('LibOQSUtils', () {
    group('uint8ListToPointer', () {
      test('throws ArgumentError for empty data', () {
        expect(
          () => LibOQSUtils.uint8ListToPointer(Uint8List(0)),
          throwsArgumentError,
        );
      });

      test('throws LibOQSException for data exceeding max size', () {
        // Create data larger than 3MB max
        final largeData = Uint8List(LibOQSUtils.maxAllocationSize + 1);
        expect(
          () => LibOQSUtils.uint8ListToPointer(largeData),
          throwsA(isA<LibOQSException>()),
        );
      });

      test('successfully converts valid data', () {
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        final ptr = LibOQSUtils.uint8ListToPointer(data);
        expect(ptr, isNot(nullptr));

        // Verify data was copied correctly
        final retrieved = ptr.asTypedList(data.length);
        expect(retrieved, equals(data));

        LibOQSUtils.freePointer(ptr);
      });

      test('converts large valid data (1MB)', () {
        final data = Uint8List(1024 * 1024); // 1MB
        for (int i = 0; i < data.length; i++) {
          data[i] = i % 256;
        }

        final ptr = LibOQSUtils.uint8ListToPointer(data);
        expect(ptr, isNot(nullptr));
        LibOQSUtils.freePointer(ptr);
      });
    });

    group('pointerToUint8List', () {
      test('returns empty list for length = 0', () {
        final ptr = calloc<Uint8>(10);
        try {
          expect(LibOQSUtils.pointerToUint8List(ptr, 0), isEmpty);
        } finally {
          calloc.free(ptr);
        }
      });

      test('returns empty list for negative length', () {
        final ptr = calloc<Uint8>(10);
        try {
          expect(LibOQSUtils.pointerToUint8List(ptr, -1), isEmpty);
          expect(LibOQSUtils.pointerToUint8List(ptr, -100), isEmpty);
        } finally {
          calloc.free(ptr);
        }
      });

      test('throws for length exceeding max size', () {
        final ptr = calloc<Uint8>(10);
        try {
          expect(
            () => LibOQSUtils.pointerToUint8List(
              ptr,
              LibOQSUtils.maxAllocationSize + 1,
            ),
            throwsA(isA<LibOQSException>()),
          );
        } finally {
          calloc.free(ptr);
        }
      });

      test('successfully converts valid pointer', () {
        final data = Uint8List.fromList([10, 20, 30, 40, 50]);
        final ptr = calloc<Uint8>(data.length);
        try {
          ptr.asTypedList(data.length).setAll(0, data);
          final result = LibOQSUtils.pointerToUint8List(ptr, data.length);
          expect(result, equals(data));
        } finally {
          calloc.free(ptr);
        }
      });
    });

    group('allocateBytes', () {
      test('throws ArgumentError for size = 0', () {
        expect(() => LibOQSUtils.allocateBytes(0), throwsArgumentError);
      });

      test('throws ArgumentError for negative size', () {
        expect(() => LibOQSUtils.allocateBytes(-1), throwsArgumentError);
        expect(() => LibOQSUtils.allocateBytes(-100), throwsArgumentError);
      });

      test('throws LibOQSException for size exceeding max', () {
        expect(
          () => LibOQSUtils.allocateBytes(LibOQSUtils.maxAllocationSize + 1),
          throwsA(isA<LibOQSException>()),
        );
      });

      test('successfully allocates valid size', () {
        final ptr = LibOQSUtils.allocateBytes(100);
        expect(ptr, isNot(nullptr));

        // Verify memory is zeroed
        final data = ptr.asTypedList(100);
        expect(data.every((b) => b == 0), isTrue);

        LibOQSUtils.freePointer(ptr);
      });

      test('allocates large valid size (1MB)', () {
        final ptr = LibOQSUtils.allocateBytes(1024 * 1024);
        expect(ptr, isNot(nullptr));
        LibOQSUtils.freePointer(ptr);
      });
    });

    group('freePointer', () {
      test('handles null pointer safely', () {
        expect(() => LibOQSUtils.freePointer(null), returnsNormally);
      });

      test('handles nullptr safely', () {
        expect(() => LibOQSUtils.freePointer(nullptr), returnsNormally);
      });

      test('frees valid pointer', () {
        final ptr = calloc<Uint8>(10);
        expect(() => LibOQSUtils.freePointer(ptr), returnsNormally);
      });
    });

    group('secureFreePointer', () {
      test('handles null pointer safely', () {
        expect(() => LibOQSUtils.secureFreePointer(null, 10), returnsNormally);
      });

      test('handles nullptr safely', () {
        expect(
          () => LibOQSUtils.secureFreePointer(nullptr, 10),
          returnsNormally,
        );
      });

      test('handles length = 0 safely', () {
        final ptr = calloc<Uint8>(10);
        expect(() => LibOQSUtils.secureFreePointer(ptr, 0), returnsNormally);
        // Pointer was not freed because length was 0, so free it now
        calloc.free(ptr);
      });

      test('handles negative length safely', () {
        final ptr = calloc<Uint8>(10);
        expect(() => LibOQSUtils.secureFreePointer(ptr, -1), returnsNormally);
        // Pointer was not freed because length was negative, so free it now
        calloc.free(ptr);
      });

      test('frees valid pointer with valid length', () {
        final ptr = calloc<Uint8>(10);
        expect(() => LibOQSUtils.secureFreePointer(ptr, 10), returnsNormally);
      });
    });

    group('validateAlgorithmName', () {
      test('throws for empty name', () {
        expect(
          () => LibOQSUtils.validateAlgorithmName(''),
          throwsArgumentError,
        );
      });

      test('throws for name too long (> 256 chars)', () {
        final longName = 'A' * 257;
        expect(
          () => LibOQSUtils.validateAlgorithmName(longName),
          throwsArgumentError,
        );
      });

      test('throws for invalid characters - space', () {
        expect(
          () => LibOQSUtils.validateAlgorithmName('alg name'),
          throwsArgumentError,
        );
      });

      test('throws for invalid characters - special chars', () {
        expect(
          () => LibOQSUtils.validateAlgorithmName('alg@name'),
          throwsArgumentError,
        );
        expect(
          () => LibOQSUtils.validateAlgorithmName('alg#name'),
          throwsArgumentError,
        );
        expect(
          () => LibOQSUtils.validateAlgorithmName('alg!name'),
          throwsArgumentError,
        );
      });

      test('accepts valid names with hyphens', () {
        expect(
          () => LibOQSUtils.validateAlgorithmName('ML-KEM-768'),
          returnsNormally,
        );
        expect(
          () => LibOQSUtils.validateAlgorithmName('ML-DSA-65'),
          returnsNormally,
        );
      });

      test('accepts valid names with underscores', () {
        expect(
          () => LibOQSUtils.validateAlgorithmName('some_algorithm'),
          returnsNormally,
        );
      });

      test('accepts valid names with plus signs', () {
        expect(
          () => LibOQSUtils.validateAlgorithmName('alg+variant'),
          returnsNormally,
        );
      });

      test('accepts valid alphanumeric names', () {
        expect(
          () => LibOQSUtils.validateAlgorithmName('Kyber512'),
          returnsNormally,
        );
        expect(
          () => LibOQSUtils.validateAlgorithmName('Dilithium3'),
          returnsNormally,
        );
      });

      test('accepts name at max length (256 chars)', () {
        final maxName = 'A' * 256;
        expect(
          () => LibOQSUtils.validateAlgorithmName(maxName),
          returnsNormally,
        );
      });
    });

    group('constantTimeEquals', () {
      test('returns true for equal arrays', () {
        final a = Uint8List.fromList([1, 2, 3, 4, 5]);
        final b = Uint8List.fromList([1, 2, 3, 4, 5]);
        expect(LibOQSUtils.constantTimeEquals(a, b), isTrue);
      });

      test('returns false for different arrays', () {
        final a = Uint8List.fromList([1, 2, 3, 4, 5]);
        final b = Uint8List.fromList([1, 2, 3, 4, 6]);
        expect(LibOQSUtils.constantTimeEquals(a, b), isFalse);
      });

      test('returns false for different lengths', () {
        final a = Uint8List.fromList([1, 2, 3]);
        final b = Uint8List.fromList([1, 2, 3, 4]);
        expect(LibOQSUtils.constantTimeEquals(a, b), isFalse);
      });

      test('returns true for empty arrays', () {
        final a = Uint8List(0);
        final b = Uint8List(0);
        expect(LibOQSUtils.constantTimeEquals(a, b), isTrue);
      });

      test('returns false when one array is empty', () {
        final a = Uint8List.fromList([1, 2, 3]);
        final b = Uint8List(0);
        expect(LibOQSUtils.constantTimeEquals(a, b), isFalse);
        expect(LibOQSUtils.constantTimeEquals(b, a), isFalse);
      });
    });

    group('zeroMemory', () {
      test('zeros data in place', () {
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        LibOQSUtils.zeroMemory(data);
        expect(data.every((b) => b == 0), isTrue);
      });

      test('handles empty data', () {
        final data = Uint8List(0);
        expect(() => LibOQSUtils.zeroMemory(data), returnsNormally);
      });

      test('zeros large data', () {
        final data = Uint8List(10000);
        for (int i = 0; i < data.length; i++) {
          data[i] = i % 256;
        }
        LibOQSUtils.zeroMemory(data);
        expect(data.every((b) => b == 0), isTrue);
      });
    });

    group('maxAllocationSize', () {
      test('is 3MB', () {
        expect(LibOQSUtils.maxAllocationSize, equals(3 * 1024 * 1024));
      });
    });
  });
}
