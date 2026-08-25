import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talentloq/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService Unit Tests & Regression Suite', () {
    late AuthService authService;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      authService = AuthService();
    });

    test('Unregistered domain email throws registration restriction exception', () async {
      expect(
        () async => await authService.register(
          fullName: 'Test Student',
          email: 'user@gmail.com',
          password: 'Password123!',
          education: 'B.Tech CS',
          cgpa: 8.5,
          skills: ['Flutter', 'Python'],
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Offline fallback with unregistered email returns generic Invalid credentials', () async {
      expect(
        () async => await authService.login(
          email: 'unregistered_random_user_12345@gsfcuniversity.ac.in',
          password: 'WrongPassword123!',
        ),
        throwsA(predicate((e) => e.toString().contains('Invalid credentials'))),
      );
    });
  });
}
