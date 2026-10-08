import 'dart:async';
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

  /// Student Registration (POST /auth/register)
  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
    String education = '',
    double cgpa = 0.0,
    int activeBacklogs = 0,
    int closedBacklogs = 0,
    List<String> skills = const [],
  }) async {
    final cleanName = fullName.trim().isEmpty ? 'Student User' : fullName.trim();
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password.trim();

    // GSFC University Domain Verification
    if (!cleanEmail.endsWith('@gsfcuniversity.ac.in') && !cleanEmail.contains('gsfcuniversity')) {
      throw Exception('Only GSFC University student emails (@gsfcuniversity.ac.in) are allowed to register.');
    }

    final cleanEducation = education.trim().isEmpty ? 'Pending Document Verification' : education.trim();
    final cleanCgpa = (cgpa < 0.0 || cgpa > 10.0) ? 0.0 : cgpa;
    final cleanSkills = skills;

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
        await _tokenStorage.saveRegisteredEmail(cleanEmail);
        // Password hashed on server; not stored in plaintext
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
      throw Exception('Cannot connect to backend server. Please make sure the backend server is reachable.');
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
          await _tokenStorage.saveIsLoggedIn(true);

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
      throw Exception('Invalid credentials or unable to reach server. Please check your connection.');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Invalid credentials or unable to reach server.');
    }
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
        await _tokenStorage.saveIsLoggedIn(true);

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
      throw Exception('Network error during OTP verification. Please verify server connection.');
    } catch (_) {
      throw Exception('Network error during OTP verification. Please verify server connection.');
    }
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

  /// Register device FCM token (POST /notifications/device-token)
  Future<bool> registerDeviceToken(String fcmToken) async {
    try {
      final response = await _dio.post(
        '/notifications/device-token',
        data: {
          'token': fcmToken,
          'platform': 'android',
          'app_version': '1.0.0',
        },
      );
      return response.statusCode == 200;
    } catch (_) {
      try {
        final legacyRes = await _dio.post(
          '/auth/device-token',
          data: {'fcm_token': fcmToken},
        );
        return legacyRes.statusCode == 200;
      } catch (_) {
        return false;
      }
    }
  }

  /// Logout (POST /auth/logout)
  Future<void> logout() async {
    try {
      try {
        await _dio.delete('/notifications/device-token');
      } catch (_) {}

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