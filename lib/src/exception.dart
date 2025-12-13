/// Enhanced exception class with more context
class LibOQSException implements Exception {
  final String message;
  final int? errorCode;
  final String? algorithmName;
  final StackTrace? stackTrace;

  LibOQSException(this.message, [this.errorCode, this.algorithmName])
    : stackTrace = StackTrace.current;

  @override
  String toString() {
    final parts = <String>['LibOQSException'];
    if (errorCode != null) parts.add('(code: $errorCode)');
    if (algorithmName != null) parts.add('[alg: $algorithmName]');
    parts.add(': $message');
    return parts.join('');
  }
}
