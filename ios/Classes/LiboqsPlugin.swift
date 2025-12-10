import Flutter

/// Minimal Flutter plugin class for liboqs FFI bindings.
public class LiboqsPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // No method channel - cryptographic functions accessed via Dart FFI
  }
}
