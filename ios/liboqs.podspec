Pod::Spec.new do |s|
  s.name             = 'liboqs'
  s.version          = '1.0.0'
  s.summary          = 'Post-quantum cryptography (liboqs) FFI bindings for Flutter'
  s.description      = 'Dart FFI bindings for liboqs with ML-KEM, ML-DSA, and other PQC algorithms.'
  s.homepage         = 'https://github.com/djx-y-z/liboqs_dart'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'liboqs_dart' => 'dev@liboqs.org' }
  s.source           = { :path => '.' }

  s.source_files = 'Classes/**/*'
  s.vendored_frameworks = 'Frameworks/liboqs.xcframework'

  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.swift_version = '5.0'

  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -force_load "${PODS_XCFRAMEWORKS_BUILD_DIR}/liboqs/liboqs.a"',
  }
end
