import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/logging/app_logger.dart';

/// Sign-in options chosen to fix Groic's #2 complaint (verification loops):
/// * Guest (anonymous) — listen in 1 tap, upgrade later without losing data.
/// * Google — one tap via Credential Manager / native sheet.
/// * Apple — required on iOS when offering Google; free, no SDK.
/// No SMS OTP: it's not free on Firebase and was the flakiest path.
class AuthRepository {
  AuthRepository(this._auth);

  final FirebaseAuth _auth;
  Future<void>? _googleInit;

  /// `userChanges` (not `authStateChanges`) so linking a guest account to
  /// Google/Apple is observed immediately (isAnonymous flips to false).
  Stream<User?> userChanges() => _auth.userChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> continueAsGuest() => _guard(_auth.signInAnonymously);

  Future<void> signInWithGoogle() => _guard(() async {
    final google = GoogleSignIn.instance;
    final GoogleSignInAccount account;
    try {
      // On Android the Web client ID comes from `default_web_client_id`, which the
      // google-services plugin generates from google-services.json (needs the Google
      // provider enabled in Firebase Auth *before* the JSON is downloaded).
      await (_googleInit ??= google.initialize());
      account = await google.authenticate();
    } on GoogleSignInException catch (e, st) {
      if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) {
        throw const AuthCancelledException();
      }
      AppLogger.error('GoogleSignIn', e, st);
      _googleInit = null; // allow a clean retry instead of caching the failure
      throw AuthException(switch (e.code) {
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError => 'Google sign-in is not configured for this build yet.',
        GoogleSignInExceptionCode.uiUnavailable => 'Google sign-in could not open here. Please try again.',
        _ => 'Google sign-in is unavailable right now.',
      }, e);
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw const AuthException('Google did not return a token.');
    await _signInOrLink(GoogleAuthProvider.credential(idToken: idToken));
  });

  Future<void> signInWithApple() => _guard(() async {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    final user = _auth.currentUser;
    if (user != null && user.isAnonymous) {
      try {
        await user.linkWithProvider(provider);
        return;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use') rethrow;
      }
    }
    await _auth.signInWithProvider(provider);
  });

  /// Upgrades a guest in place (keeps uid, username, likes) when possible;
  /// if the Google account already exists, switches to it instead.
  Future<void> _signInOrLink(AuthCredential credential) async {
    final user = _auth.currentUser;
    if (user != null && user.isAnonymous) {
      try {
        await user.linkWithCredential(credential);
        return;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'credential-already-in-use') rethrow;
      }
    }
    await _auth.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    if (_googleInit != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Not signed in with Google — ignore.
      }
    }
    await _auth.signOut();
  }

  /// Deletes the Firebase Auth user (store requirement: in-app deletion).
  Future<void> deleteUser() => _guard(() async => _auth.currentUser?.delete());

  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } on AppException {
      rethrow;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' || e.code == 'web-context-canceled' || e.code == 'user-cancelled') {
        throw const AuthCancelledException();
      }
      throw AppException.from(e);
    } catch (e) {
      throw AppException.from(e);
    }
  }
}
