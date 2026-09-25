import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../../profile/data/user_repository.dart';
import '../../profile/domain/user_profile.dart';
import '../data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(firebaseAuthProvider)));

final userRepositoryProvider = Provider<UserRepository>((ref) => UserRepository(ref.watch(firestoreProvider)));

final authUserProvider = StreamProvider<User?>((ref) => ref.watch(authRepositoryProvider).userChanges());

final _profileStreamProvider = StreamProvider<UserProfile?>((ref) {
  final uid = ref.watch(authUserProvider.select((a) => a.value?.uid));
  if (uid == null) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watch(uid);
});

/// Where the user is in the app lifecycle. The router redirects purely from
/// this value, so auth/onboarding logic lives in exactly one place.
sealed class SessionState {
  const SessionState();
}

final class SessionLoading extends SessionState {
  const SessionLoading();
}

final class SessionError extends SessionState {
  const SessionError(this.error);
  final Object error;
}

final class SignedOut extends SessionState {
  const SignedOut();
}

final class NeedsProfile extends SessionState {
  const NeedsProfile(this.user);
  final User user;
}

final class SessionReady extends SessionState {
  const SessionReady(this.user, this.profile);
  final User user;
  final UserProfile profile;
}

final sessionProvider = Provider<SessionState>((ref) {
  final auth = ref.watch(authUserProvider);
  if (auth.hasError) return SessionError(auth.error!);
  if (!auth.hasValue) return const SessionLoading();
  final user = auth.value;
  if (user == null) return const SignedOut();

  final profile = ref.watch(_profileStreamProvider);
  if (profile.hasError) return SessionError(profile.error!);
  if (!profile.hasValue) return const SessionLoading();
  final p = profile.value;
  return p == null ? NeedsProfile(user) : SessionReady(user, p);
});

/// Convenience for screens behind the onboarding gate.
final currentProfileProvider = Provider<UserProfile?>(
  (ref) => switch (ref.watch(sessionProvider)) {
    SessionReady(:final profile) => profile,
    _ => null,
  },
);

final isGuestProvider = Provider<bool>(
  (ref) => ref.watch(authUserProvider.select((a) => a.value?.isAnonymous ?? false)),
);

/// Re-subscribes the profile stream (e.g. "retry" on the splash error view).
void retrySession(WidgetRef ref) => ref.invalidate(_profileStreamProvider);
