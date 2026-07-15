import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import '../../hook/build.dart' as build_hook;

void main() {
  group('downloadCacheSubdir', () {
    test('distinguishes iOS device from iOS simulator', () {
      final device = build_hook.downloadCacheSubdir(
        version: '0.16.0-1',
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        iosSdk: IOSSdk.iPhoneOS,
      );
      final simulator = build_hook.downloadCacheSubdir(
        version: '0.16.0-1',
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        iosSdk: IOSSdk.iPhoneSimulator,
      );

      expect(
        device,
        isNot(equals(simulator)),
        reason:
            'iOS device and simulator builds share targetOS and '
            'targetArchitecture on Apple-silicon hosts. If they also share '
            'a cache key, whichever platform builds first poisons the cache '
            'for the other and dyld rejects the binary at runtime '
            "(incompatible platform: have 'iOS-simulator', need 'iOS').",
      );
    });

    test('distinguishes versions (native_version + native_build bump)', () {
      String subdirFor(String version) => build_hook.downloadCacheSubdir(
        version: version,
        targetOS: OS.macOS,
        targetArchitecture: Architecture.arm64,
      );

      // A native_version bump must invalidate the cache...
      expect(
        subdirFor('0.16.0-1'),
        isNot(equals(subdirFor('0.17.0-1'))),
        reason: 'A version bump must not reuse a previously cached binary.',
      );
      // ...and so must a native_build bump for the same liboqs version.
      expect(
        subdirFor('0.16.0-1'),
        isNot(equals(subdirFor('0.16.0-2'))),
        reason:
            'A native_build bump re-releases the same liboqs version and must '
            'not reuse a previously cached binary.',
      );
    });

    test('distinguishes architectures', () {
      final arm64 = build_hook.downloadCacheSubdir(
        version: '0.16.0-1',
        targetOS: OS.iOS,
        targetArchitecture: Architecture.arm64,
        iosSdk: IOSSdk.iPhoneSimulator,
      );
      final x64 = build_hook.downloadCacheSubdir(
        version: '0.16.0-1',
        targetOS: OS.iOS,
        targetArchitecture: Architecture.x64,
        iosSdk: IOSSdk.iPhoneSimulator,
      );

      expect(arm64, isNot(equals(x64)));
    });

    test('matches the release artifact identity', () {
      expect(
        build_hook.downloadCacheSubdir(
          version: '0.16.0-1',
          targetOS: OS.iOS,
          targetArchitecture: Architecture.arm64,
          iosSdk: IOSSdk.iPhoneOS,
        ),
        '0.16.0-1-ios-device-arm64',
      );
      expect(
        build_hook.downloadCacheSubdir(
          version: '0.16.0-1',
          targetOS: OS.iOS,
          targetArchitecture: Architecture.arm64,
          iosSdk: IOSSdk.iPhoneSimulator,
        ),
        '0.16.0-1-ios-simulator-arm64',
      );
      expect(
        build_hook.downloadCacheSubdir(
          version: '0.16.0-1',
          targetOS: OS.iOS,
          targetArchitecture: Architecture.x64,
          iosSdk: IOSSdk.iPhoneSimulator,
        ),
        '0.16.0-1-ios-simulator-x86_64',
      );
      expect(
        build_hook.downloadCacheSubdir(
          version: '0.16.0-1',
          targetOS: OS.android,
          targetArchitecture: Architecture.arm64,
        ),
        '0.16.0-1-android-arm64-v8a',
      );
      expect(
        build_hook.downloadCacheSubdir(
          version: '0.16.0-1',
          targetOS: OS.macOS,
          targetArchitecture: Architecture.x64,
        ),
        '0.16.0-1-macos-x86_64',
      );
      expect(
        build_hook.downloadCacheSubdir(
          version: '0.16.0-1',
          targetOS: OS.linux,
          targetArchitecture: Architecture.arm64,
        ),
        '0.16.0-1-linux-arm64',
      );
      expect(
        build_hook.downloadCacheSubdir(
          version: '0.16.0-1',
          targetOS: OS.windows,
          targetArchitecture: Architecture.x64,
        ),
        '0.16.0-1-windows-x86_64',
      );
    });
  });
}
