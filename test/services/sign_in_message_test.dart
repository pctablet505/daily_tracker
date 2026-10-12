import 'package:daily_tracker/services/drive_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart'
    show GoogleSignInExceptionCode;

/// Google's sign-in reports a window the user closed and an app setup Google does not
/// accept (a wrong client id or signing key) as the same "canceled", so the message
/// must not blame the user alone.
void main() {
  test('a cancelled sign-in says to try again and names the app setup', () {
    final text = signInFailureMessage(GoogleSignInExceptionCode.canceled);
    expect(text, contains('try again'));
    expect(text, contains('this build of the app'));
  });

  test('it no longer claims only that the user cancelled', () {
    expect(
      signInFailureMessage(GoogleSignInExceptionCode.canceled),
      isNot('Sign-in was cancelled.'),
    );
  });

  test('any other failure names its code so it can be looked up', () {
    for (final code in GoogleSignInExceptionCode.values) {
      if (code == GoogleSignInExceptionCode.canceled) continue;
      expect(
        signInFailureMessage(code),
        'Could not sign in to Google (${code.name}).',
      );
    }
  });
}
