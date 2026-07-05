class AiScanCancelledException implements Exception {
  const AiScanCancelledException();

  @override
  String toString() => 'AI scan cancelled by user.';
}

class AiScanCancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const AiScanCancelledException();
    }
  }
}
