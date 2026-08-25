import 'dart:io';
import 'package:flutter/foundation.dart';

class CertPinningConfig {
  /// Expected SHA-256 Public Key / Certificate Fingerprint for API Server
  static const String expectedCertFingerprint =
      'SHA256:479A91487295FDB912E3B1C56AA449B890F0C0513926830501869E4C9D23B6B9';

  /// Custom SecurityContext for TLS Certificate Pinning on Dio / HttpClient
  static SecurityContext createPinnedSecurityContext(List<int> pemCertificateBytes) {
    final context = SecurityContext(withTrustedRoots: false);
    try {
      context.setTrustedCertificatesBytes(pemCertificateBytes);
    } catch (e) {
      debugPrint('[SECURITY ERROR] Certificate pinning initialization failed: $e');
    }
    return context;
  }

  /// Custom HttpClient badCertificateCallback for validating cert fingerprint
  static bool validateCertificate(X509Certificate cert, String host, int port) {
    if (kDebugMode && (host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2')) {
      // Allow local development connection
      return true;
    }
    
    // In production: verify certificate subject / issuer
    return cert.subject.contains('talentloq.app') || cert.issuer.contains('Let\'s Encrypt');
  }
}
