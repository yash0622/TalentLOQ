import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

class CertPinningConfig {
  /// Expected SHA-256 Public Key / Certificate Fingerprint for API Server
  static const String expectedCertFingerprint =
      '479A91487295FDB912E3B1C56AA449B890F0C0513926830501869E4C9D23B6B9';

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
    if (kDebugMode) {
      // Allow local development connections, LAN IPs, and ngrok development tunnels
      if (host == 'localhost' ||
          host == '127.0.0.1' ||
          host == '10.0.2.2' ||
          host.endsWith('ngrok-free.dev') ||
          host.endsWith('ngrok.app') ||
          host.endsWith('ngrok.io') ||
          host.startsWith('10.') ||
          host.startsWith('192.168.')) {
        return true;
      }
    }

    // Compare SHA-256 fingerprint of the certificate DER bytes
    try {
      final certDer = cert.der;
      final sha256Digest = sha256.convert(certDer).toString().toUpperCase();
      final cleanExpected = expectedCertFingerprint.replaceAll(':', '').replaceAll(' ', '').toUpperCase();
      if (sha256Digest == cleanExpected) {
        return true;
      }
    } catch (e) {
      debugPrint('[CERT PINNING ERROR] $e');
    }

    // In production: verify subject matches verified domain
    return cert.subject.contains('talentloq.app');
  }
}
