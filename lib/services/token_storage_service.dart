import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

class TokenStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _keyAccessToken = 'talentloq_access_token';
  static const String _keyRefreshToken = 'talentloq_refresh_token';
  static const String _keyDeviceId = 'talentloq_device_id';
  static const String _keyUserRole = 'talentloq_user_role';

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

  /// Save user registered email flag
  Future<void> saveRegisteredEmail(String email) async {
    await _storage.write(key: 'reg_user_${email.toLowerCase().trim()}', value: 'true');
  }

  /// Check if user has registered
  Future<bool> isRegisteredUser(String email) async {
    final res = await _storage.read(key: 'reg_user_${email.toLowerCase().trim()}');
    return res == 'true';
  }

  /// Save user registered password securely for credential validation
  Future<void> saveUserPassword(String email, String password) async {
    await _storage.write(key: 'user_pass_${email.toLowerCase().trim()}', value: password);
  }

  /// Get registered password for email
  Future<String?> getUserPassword(String email) async {
    return await _storage.read(key: 'user_pass_${email.toLowerCase().trim()}');
  }

  /// Check if an email address has been registered
  Future<bool> isEmailRegistered(String email) async {
    return await isRegisteredUser(email);
  }

  /// Get or generate a persistent device ID stored in secure storage
  Future<String> getOrCreateDeviceId() async {
    String? deviceId = await _storage.read(key: _keyDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = 'dev-${const Uuid().v4().substring(0, 12)}';
      await _storage.write(key: _keyDeviceId, value: deviceId);
    }
    return deviceId;
  }

  /// Clear all stored tokens on logout
  Future<void> clearTokens() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyUserRole);
  }

  /// Save Student Profile Data
  Future<void> saveStudentProfile({
    required String email,
    String? fullName,
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
    final education = await _storage.read(key: 'profile_education') ?? 'B.Tech CSE';
    final cgpaStr = await _storage.read(key: 'profile_cgpa') ?? '7.9';
    final activeStr = await _storage.read(key: 'profile_active_backlogs') ?? '0';
    final closedStr = await _storage.read(key: 'profile_closed_backlogs') ?? '2';
    final skillsStr = await _storage.read(key: 'profile_skills') ?? 'Python,React JS';

    final skillsList = skillsStr.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    return {
      'email': email,
      'full_name': fullName,
      'education': education,
      'cgpa': double.tryParse(cgpaStr) ?? 7.9,
      'active_backlogs': int.tryParse(activeStr) ?? 0,
      'closed_backlogs': int.tryParse(closedStr) ?? 2,
      'skills': skillsList.isEmpty ? ['Python', 'React JS'] : skillsList,
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
}
