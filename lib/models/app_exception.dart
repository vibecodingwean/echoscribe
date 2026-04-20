/// Base exception for all app-level errors.
/// Carries a user-facing [userMessage] and an optional technical [internalMessage].
class AppException implements Exception {
  final String userMessage;
  final String? internalMessage;

  const AppException(this.userMessage, {this.internalMessage});

  @override
  String toString() => internalMessage ?? userMessage;

  /// Creates the appropriate [AppException] subtype from an HTTP status code
  /// and an optional API error message.
  factory AppException.fromHttp(int statusCode,
      {String? apiMessage, String? fallback}) {
    final detail = apiMessage ?? fallback ?? 'Request failed ($statusCode)';
    switch (statusCode) {
      case 401:
        return AuthException(apiMessage ?? 'Invalid API key');
      case 403:
        return AuthException(
            apiMessage ?? 'Access denied - check your API key permissions');
      case 429:
        return QuotaException(
            apiMessage ?? 'Rate limit exceeded - please wait and try again');
      case >= 500:
        return ServerException(detail);
      default:
        return AppException(detail,
            internalMessage: 'HTTP $statusCode: $detail');
    }
  }
}

/// Authentication or authorization error (401, 403).
class AuthException extends AppException {
  const AuthException(super.userMessage, {super.internalMessage});
}

/// Rate-limit or quota exceeded (429).
class QuotaException extends AppException {
  const QuotaException(super.userMessage, {super.internalMessage});
}

/// Server-side error (5xx).
class ServerException extends AppException {
  const ServerException(super.userMessage, {super.internalMessage});
}

/// Network connectivity error (SocketException, TimeoutException).
class NetworkException extends AppException {
  const NetworkException(
      [super.userMessage = 'Network error - check your connection']);
}

/// The AI returned an empty or unusable result.
class EmptyResultException extends AppException {
  const EmptyResultException(
      [super.userMessage = 'AI returned an empty result']);
}
