import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _keyAccessToken = 'talentloq_access_token';
  static const String _keyRefreshToken = 'talentloq_refresh_token';
  static const String _keyDeviceId = 'talentloq_device_id';
  static const String _keyUserRole = 'talentloq_user_role';
  static const String _keyIsLoggedIn = 'talentloq_is_logged_in';

  /// Save Access Token
  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: _keyAccessToken, value: token);
  }

  /// Get Access Token
  Future<String?> getAccessToken() async {
    return await _storage.read(key: _keyAccessToken);
  }

  /// Save Refresh Token
  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _keyRefreshToken, value: token);
  }

  /// Get Refresh Token
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _keyRefreshToken);
  }

  /// Save User Role
  Future<void> saveUserRole(String role) async {
    await _storage.write(key: _keyUserRole, value: role);
  }

  /// Get User Role
  Future<String?> getUserRole() async {
    return await _storage.read(key: _keyUserRole);
  }
  /// Save user logged-in status
  Future<void> saveIsLoggedIn(bool isLoggedIn) async {
    await _storage.write(key: _keyIsLoggedIn, value: isLoggedIn ? 'true' : 'false');
  }

  /// Check if user is logged in
  Future<bool> getIsLoggedIn() async {
    final status = await _storage.read(key: _keyIsLoggedIn);
    if (status == 'true') return true;
    final token = await getAccessToken();
    final refresh = await getRefreshToken();
    return (token != null && token.isNotEmpty) || (refresh != null && refresh.isNotEmpty);
  }


  /// Save user registered email flag
  Future<void> saveRegisteredEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    await _storage.write(key: 'reg_user_$cleanEmail', value: 'true');
  }

  /// Check if user has registered
  Future<bool> isRegisteredUser(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    final res = await _storage.read(key: 'reg_user_$cleanEmail');
    return res == 'true';
  }

  /// Check if an email address has been registered
  Future<bool> isEmailRegistered(String email) async {
    return await isRegisteredUser(email);
  }

  /// Get or generate a persistent device ID stored in secure storage
  Future<String> getOrCreateDeviceId() async {
    String? deviceId = await _storage.read(key: _keyDeviceId);
    if (deviceId == null || deviceId.isEmpty || deviceId == 'dev-') {
      final rand = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      deviceId = 'dev-$rand';
      await _storage.write(key: _keyDeviceId, value: deviceId);
    }
    return deviceId;
  }

  /// Clear all stored tokens on logout
  Future<void> clearTokens() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyUserRole);
    await _storage.delete(key: _keyIsLoggedIn);
    await clearProfile();
  }

  /// Save Student Profile Data
  Future<void> saveStudentProfile({
    required String email,
    String? fullName,
    String? university,
    required String education,
    required double cgpa,
    required int activeBacklogs,
    required int closedBacklogs,
    required List<String> skills,
  }) async {
    await _storage.write(key: 'profile_email', value: email);
    if (fullName != null && fullName.isNotEmpty) {
      await _storage.write(key: 'profile_full_name', value: fullName);
    }
    if (university != null && university.isNotEmpty) {
      await _storage.write(key: 'profile_university', value: university);
    }
    await _storage.write(key: 'profile_education', value: education);
    await _storage.write(key: 'profile_cgpa', value: cgpa.toString());
    await _storage.write(key: 'profile_active_backlogs', value: activeBacklogs.toString());
    await _storage.write(key: 'profile_closed_backlogs', value: closedBacklogs.toString());
    await _storage.write(key: 'profile_skills', value: skills.join(','));
  }

  /// Get Student Profile Data
  Future<Map<String, dynamic>> getStudentProfile() async {
    final email = await _storage.read(key: 'profile_email') ?? '';
    final fullName = await _storage.read(key: 'profile_full_name') ?? '';
    final university = await _storage.read(key: 'profile_university') ?? 'GSFC University';
    final education = await _storage.read(key: 'profile_education') ?? '';
    final cgpaStr = await _storage.read(key: 'profile_cgpa') ?? '';
    final activeStr = await _storage.read(key: 'profile_active_backlogs') ?? '0';
    final closedStr = await _storage.read(key: 'profile_closed_backlogs') ?? '0';
    final skillsStr = await _storage.read(key: 'profile_skills') ?? '';

    final skillsList = skillsStr.trim().isEmpty
        ? <String>[]
        : skillsStr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    return {
      'email': email,
      'full_name': fullName,
      'university': university,
      'education': education,
      'cgpa': double.tryParse(cgpaStr) ?? 0.0,
      'active_backlogs': int.tryParse(activeStr) ?? 0,
      'closed_backlogs': int.tryParse(closedStr) ?? 0,
      'skills': skillsList,
    };
  }

  /// Save Student Resume Info
  Future<void> saveResume({required String fileName, required String filePath}) async {
    await _storage.write(key: 'profile_resume_name', value: fileName);
    await _storage.write(key: 'profile_resume_path', value: filePath);
  }

  /// Get Student Resume Info
  Future<Map<String, String?>> getResume() async {
    final fileName = await _storage.read(key: 'profile_resume_name');
    final filePath = await _storage.read(key: 'profile_resume_path');
    return {'fileName': fileName, 'filePath': filePath};
  }

  /// Clear Resume
  Future<void> clearResume() async {
    await _storage.delete(key: 'profile_resume_name');
    await _storage.delete(key: 'profile_resume_path');
  }

  /// Clear Student Profile Data
  Future<void> clearProfile() async {
    await _storage.delete(key: 'profile_email');
    await _storage.delete(key: 'profile_full_name');
    await _storage.delete(key: 'profile_university');
    await _storage.delete(key: 'profile_education');
    await _storage.delete(key: 'profile_cgpa');
    await _storage.delete(key: 'profile_active_backlogs');
    await _storage.delete(key: 'profile_closed_backlogs');
    await _storage.delete(key: 'profile_skills');
    await clearResume();
  }
}