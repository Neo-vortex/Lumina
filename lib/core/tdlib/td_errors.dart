/// A TDLib `error` object returned for an invoke, raised as an exception.
class TdException implements Exception {
  const TdException(this.code, this.message);

  final int code;
  final String message;

  /// Seconds to wait when TDLib rate-limited the request, or null.
  ///
  /// TDLib reports flood waits either as the raw server error
  /// (`FLOOD_WAIT_42`) or as `429: Too Many Requests: retry after 42`.
  int? get floodWaitSeconds {
    final match = _floodWait.firstMatch(message) ?? _retryAfter.firstMatch(message);
    if (match != null) return int.parse(match.group(1)!);
    return null;
  }

  bool get isFloodWait => floodWaitSeconds != null;

  /// True when [message] names the server error [name] (e.g. `PHONE_CODE_INVALID`).
  bool hasServerError(String name) => message.contains(name);

  static final _floodWait = RegExp(r'FLOOD_WAIT_(\d+)');
  static final _retryAfter = RegExp(r'retry after (\d+)', caseSensitive: false);

  @override
  String toString() => 'TdException($code): $message';
}

/// The invoke never got a usable answer (client closed, parse failure, timeout).
class TdTransportException implements Exception {
  const TdTransportException(this.message);
  final String message;

  @override
  String toString() => 'TdTransportException: $message';
}
