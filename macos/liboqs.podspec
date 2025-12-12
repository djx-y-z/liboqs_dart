Pod::Spec.new do |s|
  s.name             = 'liboqs'
  s.version          = '1.0.0'
  s.summary          = 'Post-quantum cryptography (liboqs) FFI bindings for Flutter'
  s.description      = <<-DESC
Dart FFI bindings for liboqs — high-performance post-quantum cryptography (PQC)
with ML-KEM, ML-DSA, Falcon, SPHINCS+ for key encapsulation and signatures.
                       DESC
  s.homepage         = 'https://github.com/djx-y-z/liboqs_dart'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'liboqs_dart' => 'dev@liboqs.org' }
  s.source           = { :path => '.' }

  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.swift_version = '5.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Ensure the dylib is found at runtime (Build Hooks place it in Frameworks)
    'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks'
  }
end
