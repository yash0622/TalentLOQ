import 'dart:convert';

class JwtDecoderUtil {
  /// Decodes base64 payload of a JWT token safely.
  static Map<String, dynamic>? decodeTokenPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      String payload = parts[1];
      // Normalize base64 URL padding
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      final decodedBytes = base64Url.decode(payload);
      final jsonStr = utf8.decode(decodedBytes);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Derives user role ('student' | 'recruiter') from valid JWT token
  static String? getRoleFromToken(String token) {
    final payload = decodeTokenPayload(token);
    return payload?['role'] as String?;
  }

  /// Derives user ID from valid JWT token
  static String? getUserIdFromToken(String token) {
    final payload = decodeTokenPayload(token);
    return payload?['sub'] as String?;
  }

  /// Checks if token is expired
  static bool isTokenExpired(String token) {
    final payload = decodeTokenPayload(token);
    if (payload == null || !payload.containsKey('exp')) return true;

    final expSeconds = payload['exp'] as int;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return nowSeconds >= expSeconds;
  }
}
