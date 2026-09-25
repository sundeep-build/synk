import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:synk/app/router/app_router.dart';
import 'package:synk/app/router/routes.dart';
import 'package:synk/features/auth/application/session.dart';
import 'package:synk/features/profile/domain/user_profile.dart';

class _MockUser extends Mock implements User {}

void main() {
  final user = _MockUser();
  const profile = UserProfile(uid: 'u', username: 'maya', displayName: 'maya', avatarEmoji: '🎧', avatarColor: 0);

  String? go(SessionState s, String location) => redirectFor(s, location, Uri.parse(location));

  test('signed-out users land on welcome', () {
    expect(go(const SignedOut(), Routes.home), '/welcome?from=%2Fhome');
    expect(go(const SignedOut(), Routes.welcome), isNull);
  });

  test('users without a profile are sent to onboarding', () {
    expect(go(NeedsProfile(user), Routes.welcome), Routes.onboarding);
  });

  test('ready users leave the gate for home', () {
    expect(go(SessionReady(user, profile), Routes.welcome), Routes.home);
    expect(go(SessionReady(user, profile), Routes.library), isNull);
  });

  test('invite deep links survive sign-in and onboarding', () {
    final atWelcome = go(const SignedOut(), '/join/ABC234')!;
    expect(atWelcome, startsWith(Routes.welcome));

    final uri = Uri.parse(atWelcome);
    final atOnboarding = redirectFor(NeedsProfile(user), uri.path, uri)!;
    expect(Uri.parse(atOnboarding).queryParameters['from'], '/join/ABC234');

    final back = Uri.parse(atOnboarding);
    expect(redirectFor(SessionReady(user, profile), back.path, back), '/join/ABC234');
  });

  test('loading and errors wait on the splash screen', () {
    expect(go(const SessionLoading(), Routes.home), startsWith(Routes.splash));
    expect(go(SessionError(Exception('x')), Routes.splash), isNull);
  });
}
