Pod::Spec.new do |s|
  s.name             = 'liboqs'
  s.version          = '1.0.0'
  s.summary          = 'Post-quantum cryptography (liboqs) FFI bindings for Flutter'
  s.description      = <<-DESC
Dart FFI bindings for liboqs — high-performance post-quantum cryptography (PQC)
with ML-KEM, ML-DSA, Falcon, SPHINCS+ for key encapsulation and signatures.
Native libraries are statically linked via this podspec for iOS.
                       DESC
  s.homepage         = 'https://github.com/djx-y-z/liboqs_dart'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'liboqs_dart' => 'dev@liboqs.org' }
  s.source           = { :path => '.' }

  s.source_files = 'Classes/**/*'

  # Use xcframework with static libraries for all iOS architectures
  # The xcframework is created by CI and contains device + simulator
  s.vendored_frameworks = 'Frameworks/liboqs.xcframework'

  # Static library linkage configuration
  s.static_framework = true

  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.swift_version = '5.0'
end
