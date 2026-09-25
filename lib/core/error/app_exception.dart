import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

/// Every error that reaches the UI is mapped to one of these, so screens only
/// ever show friendly copy and never raw platform messages.
sealed class AppException implements Exception {
  const AppException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  static AppException from(Object error) {
    if (error is AppException) return error;
    if (error is SocketException || error is TimeoutException) {
      return NetworkException(cause: error);
    }
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'network-request-failed' => NetworkException(cause: error),
        'credential-already-in-use' || 'account-exists-with-different-credential' => AuthException(
          'That account is already linked to another profile.',
          error,
        ),
        'requires-recent-login' => AuthException('Please sign in again to continue.', error),
        'user-disabled' => AuthException('This account has been disabled.', error),
        // Provider not switched on in Firebase console → Authentication → Sign-in method.
        'operation-not-allowed' || 'admin-restricted-operation' => AuthException(
          'This sign-in option is not enabled yet. Please try another one.',
          error,
        ),
        _ => AuthException('Sign-in failed. Please try again.', error),
      };
    }
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => PermissionException(cause: error),
        'unavailable' || 'deadline-exceeded' => NetworkException(cause: error),
        'not-found' => NotFoundException(cause: error),
        _ => UnknownException(cause: error),
      };
    }
    return UnknownException(cause: error);
  }

  @override
  String toString() => '$runtimeType: $message${cause == null ? '' : ' ($cause)'}';
}

final class NetworkException extends AppException {
  const NetworkException({Object? cause}) : super("You're offline or the connection is weak. Try again.", cause);
}

final class AuthException extends AppException {
  const AuthException(super.message, [super.cause]);
}

/// The user backed out of a sign-in sheet. UI should stay silent.
final class AuthCancelledException extends AppException {
  const AuthCancelledException() : super('Sign-in cancelled.');
}

final class PermissionException extends AppException {
  const PermissionException({Object? cause}) : super("You don't have access to do that.", cause);
}

final class NotFoundException extends AppException {
  const NotFoundException({String message = "We couldn't find that.", Object? cause}) : super(message, cause);
}

final class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// A non-retryable HTTP error from a third-party API (after our own mapping).
final class HttpStatusException extends AppException {
  const HttpStatusException(this.statusCode, {Object? cause}) : super('Something went wrong. Please try again.', cause);

  final int statusCode;
}

/// A third-party service refused the request for a reason the user can't fix
/// right now (e.g. YouTube's daily quota is used up).
final class ServiceUnavailableException extends AppException {
  const ServiceUnavailableException(super.message, [super.cause]);
}

/// Built without a YOUTUBE_API_KEY: the app runs radio-only.
final class YouTubeNotConfiguredException extends AppException {
  const YouTubeNotConfiguredException() : super('Videos are not enabled in this build yet.');
}

final class RoomFullException extends AppException {
  const RoomFullException() : super('This room is full right now.');
}

final class UnknownException extends AppException {
  const UnknownException({Object? cause}) : super('Something went wrong. Please try again.', cause);
}
