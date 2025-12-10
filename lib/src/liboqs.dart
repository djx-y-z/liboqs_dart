import 'base.dart';
import 'kem.dart';
import 'signature.dart';

/// Main LibOQS class for initialization and global operations
class LibOQS {
  /// Initialize the liboqs library
  /// Call this before using any other functions
  /// This is optional but recommended for better performance
  static void init() {
    LibOQSBase.init();
  }

  /// Clean up liboqs resources
  /// Call this when you're done using the library
  /// This function frees prefetched OpenSSL objects
  static void cleanup() {
    LibOQSBase.cleanup();
  }

  /// Get the version of liboqs
  static String getVersion() {
    return LibOQSBase.getVersion();
  }

  /// Get all supported KEM algorithms
  static List<String> getSupportedKEMAlgorithms() {
    return KEM.getSupportedKemAlgorithms();
  }

  /// Get all supported signature algorithms
  static List<String> getSupportedSignatureAlgorithms() {
    return Signature.getSupportedSignatureAlgorithms();
  }

  /// Check if a KEM algorithm is supported
  static bool isKEMSupported(String algorithmName) {
    return KEM.isSupported(algorithmName);
  }

  /// Check if a signature algorithm is supported
  static bool isSignatureSupported(String algorithmName) {
    return Signature.isSupported(algorithmName);
  }
}
