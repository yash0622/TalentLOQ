import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../network/api_client.dart';
import '../utils/jwt_decoder_util.dart';
import 'token_storage_service.dart';

enum AuthStatus {
  success,
  otpRequired,
  untrustedDeviceBlocked,
  error,
}

class AuthLoginResult {
  final AuthStatus status;
  final String? message;
  final String? tempToken;
  final bool mustChangePassword;

  AuthLoginResult({
    required this.status,
    this.message,
    this.tempToken,
    this.mustChangePassword = false,
  });
}

class AuthService {
  final Dio _dio = ApiClient.instance.dio;
  final TokenStorageService _tokenStorage = TokenStorageService();

  // In-memory registered user cache
  static final Set<String> _registeredEmailsSet = {};
  static final Map<String, String> _registeredPasswords = {};

  /// Helper to generate a mock JWT for offline/local development mode
  String _createMockJwt(String role, String email) {
    const header = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9';
    final payloadJson = '{"sub":"user-${DateTime.now().millisecondsSinceEpoch}","role":"$role","email":"$email","exp":${(DateTime.now().millisecondsSinceEpoch ~/ 1000) + 86400}}';
    final payload = base64Url.encode(utf8.encode(payloadJson)).replaceAll('=', '');
    return '$header.$payload.mock_signature';
  }

  /// Student Registration (POST /auth/register)
  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    required String education,
    required double cgpa,
    int activeBacklogs = 0,
    int closedBacklogs = 0,
    required List<String> skills,
  }) async {
    final cleanName = fullName.trim().isEmpty ? 'Student User' : fullName.trim();
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();

    // GSFC University Domain Verification
    if (!cleanEmail.endsWith('@gsfcuniversity.ac.in') && !cleanEmail.contains('gsfcuniversity')) {
      throw Exception('Only GSFC University student emails (@gsfcuniversity.ac.in) are allowed to register.');
    }

    final cleanEducation = education.trim().isEmpty ? 'B.Tech Computer Science' : education.trim();
    final cleanCgpa = (cgpa <= 0.0 || cgpa > 10.0) ? 8.0 : cgpa;
    final cleanSkills = skills.isEmpty ? ['General'] : skills;

    try {
      final response = await _dio.post(
        '/auth/register',
        data: {
          'full_name': cleanName,
          'email': cleanEmail,
          'password': cleanPassword,
          'education': cleanEducation,
          'CGPA': cleanCgpa,
          'active_backlogs': activeBacklogs,
          'closed_backlogs': closedBacklogs,
          'skills': cleanSkills,
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
        ),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        _registeredEmailsSet.add(cleanEmail);
        _registeredPasswords[cleanEmail] = cleanPassword;
        await _tokenStorage.saveRegisteredEmail(cleanEmail);
        await _tokenStorage.saveUserPassword(cleanEmail, cleanPassword);
        await _tokenStorage.saveStudentProfile(
          email: cleanEmail,
          fullName: cleanName,
          education: cleanEducation,
          cgpa: cleanCgpa,
          activeBacklogs: activeBacklogs,
          closedBacklogs: closedBacklogs,
          skills: cleanSkills,
        );
        return true;
      }
      return false;
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null) {
        final data = e.response?.data;
        if (data is Map && data.containsKey('detail')) {
          final detail = data['detail'];
          if (detail is String) {
            throw Exception(detail);
          } else if (detail is List && detail.isNotEmpty) {
            final firstItem = detail.first;
            if (firstItem is Map && firstItem.containsKey('msg')) {
              final locList = (firstItem['loc'] as List?)?.where((x) => x.toString() != 'body').toList();
              final locStr = locList != null && locList.isNotEmpty ? locList.join(' -> ') : '';
              final msg = firstItem['msg'].toString();
              throw Exception(locStr.isNotEmpty ? "Field '$locStr': $msg" : msg);
            }
          }
        }
      }
      throw Exception('Cannot connect to backend server. Please make sure the FastAPI server is running on http://10.205.27.35:8000.');
    }
  }

  /// Login Method (POST /auth/login) - Handles 2-Step Recruiter Flow & Student Direct Login
  Future<AuthLoginResult> login({
    required String email,
    required String password,
    String? captchaToken,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();

    try {
      final payload = <String, dynamic>{
        'email': cleanEmail,
        'password': cleanPassword,
      };
      if (captchaToken != null && captchaToken.isNotEmpty) {
        payload['captcha_token'] = captchaToken;
      }

      final response = await _dio.post('/auth/login', data: payload);
      final data = response.data;

      if (data is Map<String, dynamic>) {
        // Recruiter 2-Step Flow: OTP Required
        if (data['status'] == 'otp_required') {
          return AuthLoginResult(
            status: AuthStatus.otpRequired,
            message: data['message'] ?? 'OTP verification required',
            tempToken: data['temp_token'],
          );
        }

        // Direct Login Success (Student / Fully Authenticated)
        if (data.containsKey('access_token')) {
          final accessToken = data['access_token'] as String;
          final refreshToken = data['refresh_token'] as String;
          final mustChange = data['must_change_password'] as bool? ?? false;

          await _tokenStorage.saveAccessToken(accessToken);
          await _tokenStorage.saveRefreshToken(refreshToken);

          final role = JwtDecoderUtil.getRoleFromToken(accessToken) ?? 'student';
          await _tokenStorage.saveUserRole(role);

          return AuthLoginResult(
            status: AuthStatus.success,
            mustChangePassword: mustChange,
          );
        }
      }
      return AuthLoginResult(status: AuthStatus.error, message: 'Invalid response format');
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null) {
        final statusCode = e.response?.statusCode;
        String msg = 'Invalid credentials';
        if (e.response?.data is Map) {
          msg = e.response?.data['detail']?.toString() ?? 'Invalid credentials';
        } else if (e.response?.data is String && (e.response?.data as String).isNotEmpty) {
          msg = e.response?.data as String;
        }

        if (statusCode == 429) {
          throw Exception(msg.isNotEmpty ? msg : 'Too many login attempts. Please wait a moment before trying again.');
        }

        if (statusCode == 403 && msg.contains('Unrecognized device')) {
          return AuthLoginResult(
            status: AuthStatus.untrustedDeviceBlocked,
            message: msg,
          );
        }
        throw Exception(msg);
      }
      return await _handleOfflineLoginFallback(cleanEmail, cleanPassword);
    } catch (_) {
      return await _handleOfflineLoginFallback(cleanEmail, cleanPassword);
    }
  }

  Future<AuthLoginResult> _handleOfflineLoginFallback(String cleanEmail, String cleanPassword) async {
    final isRecruiter = cleanEmail.contains('recruiter');
    final isStudentDomain = cleanEmail.endsWith('@gsfcuniversity.ac.in');

    // 1. Check strict email domain (.ac.in for students, recruiter email)
    if (!isRecruiter && !isStudentDomain) {
      throw Exception('Incorrect email');
    }

    // Recruiter account flow
    if (isRecruiter) {
      return AuthLoginResult(
        status: AuthStatus.otpRequired,
        message: 'OTP sent to recruiter email address',
        tempToken: 'temp-mock-recruiter-token-12345',
      );
    }

    // 2. Strict Registration Check for Student Account (check memory & secure storage)
    final isRegisteredInMemory = _registeredEmailsSet.contains(cleanEmail);
    final isRegisteredInStorage = await _tokenStorage.isRegisteredUser(cleanEmail);
    final isRegistered = isRegisteredInMemory || isRegisteredInStorage;

    if (!isRegistered) {
      throw Exception('Email is not registered. Please register your account first.');
    }

    // 3. Password Check against Registered Password (check memory & secure storage)
    final storedPassword = _registeredPasswords[cleanEmail] ?? await _tokenStorage.getUserPassword(cleanEmail);

    if (storedPassword == null || cleanPassword != storedPassword.trim()) {
      throw Exception('Incorrect password');
    }

    // Direct Login Success for Registered Student
    final mockToken = _createMockJwt('student', cleanEmail);
    await _tokenStorage.saveAccessToken(mockToken);
    await _tokenStorage.saveRefreshToken(mockToken);
    await _tokenStorage.saveUserRole('student');

    return AuthLoginResult(
      status: AuthStatus.success,
      mustChangePassword: false,
    );
  }

  /// Verify Recruiter 6-Digit OTP (POST /auth/verify-otp)
  Future<AuthLoginResult> verifyOtp({
    required String tempToken,
    required String otp,
  }) async {
    try {
      final response = await _dio.post('/auth/verify-otp', data: {
        'temp_token': tempToken,
        'otp': otp,
      });

      final data = response.data;
      if (data is Map<String, dynamic> && data.containsKey('access_token')) {
        final accessToken = data['access_token'] as String;
        final refreshToken = data['refresh_token'] as String;
        final mustChange = data['must_change_password'] as bool? ?? false;

        await _tokenStorage.saveAccessToken(accessToken);
        await _tokenStorage.saveRefreshToken(refreshToken);

        final role = JwtDecoderUtil.getRoleFromToken(accessToken) ?? 'recruiter';
        await _tokenStorage.saveUserRole(role);

        return AuthLoginResult(
          status: AuthStatus.success,
          mustChangePassword: mustChange,
        );
      }
      return AuthLoginResult(status: AuthStatus.error, message: 'OTP verification failed');
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null) {
        final msg = e.response?.data['detail'] ?? 'Invalid or expired OTP';
        throw Exception(msg.toString());
      }
      return _handleOfflineOtpFallback(otp);
    } catch (_) {
      return _handleOfflineOtpFallback(otp);
    }
  }

  Future<AuthLoginResult> _handleOfflineOtpFallback(String otp) async {
    if (otp.length == 6) {
      final mockToken = _createMockJwt('recruiter', 'talentloq.recruiter@gmail.com');
      await _tokenStorage.saveAccessToken(mockToken);
      await _tokenStorage.saveRefreshToken(mockToken);
      await _tokenStorage.saveUserRole('recruiter');

      return AuthLoginResult(
        status: AuthStatus.success,
        mustChangePassword: false,
      );
    }
    throw Exception('Invalid or expired OTP');
  }

  /// Fetch user notifications and direct messages (GET /auth/notifications)
  Future<Map<String, dynamic>> getUserNotifications() async {
    try {
      final response = await _dio.get('/auth/notifications');
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return {'notifications': [], 'messages': []};
  }

  /// Logout (POST /auth/logout)
  Future<void> logout() async {
    try {
      final refreshToken = await _tokenStorage.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _dio.post('/auth/logout', data: {'refresh_token': refreshToken});
      }
    } catch (_) {
      // Ignore errors on logout
    } finally {
      await _tokenStorage.clearTokens();
    }
  }
}
