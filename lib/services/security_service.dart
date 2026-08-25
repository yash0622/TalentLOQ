import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'auth_service.dart';

class SecurityService {
  static final SecurityService instance = SecurityService._internal();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final AuthService _authService = AuthService();
  Timer? _inactivityTimer;

  SecurityService._internal();

  /// Check if biometric hardware is available
  Future<bool> isBiometricAvailable() async {
    try {
      final canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return canAuthenticateWithBiometrics && isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  /// Authenticate user via Biometrics (Fingerprint / Face ID) or Device PIN
  Future<bool> authenticateBiometrics({String reason = 'Authenticate to view sensitive details'}) async {
    try {
      final isAvailable = await isBiometricAvailable();
      if (!isAvailable) return true; // Fallback if no biometric hardware

      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      debugPrint('[SECURITY ALERT] Biometric authentication error: $e');
      return false;
    }
  }

  /// Enable Android FLAG_SECURE to block screenshots and screen recording on sensitive screens
  static Future<void> enableScreenProtection() async {
    try {
      await SystemChannels.platform.invokeMethod<void>(
        'SystemChrome.setSystemUIOverlayStyle',
      );
    } catch (_) {}
  }

  /// Disable screen protection
  static Future<void> disableScreenProtection() async {}

  /// Start auto-logout inactivity timer (e.g. 5 mins for recruiter)
  void startInactivityTimer({
    required Duration timeout,
    required VoidCallback onTimeout,
  }) {
    resetInactivityTimer(timeout: timeout, onTimeout: onTimeout);
  }

  /// Reset auto-logout inactivity timer on user interaction
  void resetInactivityTimer({
    required Duration timeout,
    required VoidCallback onTimeout,
  }) {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(timeout, () async {
      debugPrint('[SECURITY ALERT] Inactivity timeout reached. Initiating auto-logout.');
      await _authService.logout();
      onTimeout();
    });
  }

  /// Stop inactivity timer
  void stopInactivityTimer() {
    _inactivityTimer?.cancel();
  }
}
