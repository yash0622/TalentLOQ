import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:talentloq/utils/jwt_decoder_util.dart';

void main() {
  group('JwtDecoderUtil - Unit Tests', () {
    // Helper to generate mock JWT tokens for testing
    String createMockJwt(Map<String, dynamic> payload) {
      final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'}))).replaceAll('=', '');
      final body = base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
      const signature = 'mock_signature_bytes';
      return '$header.$body.$signature';
    }

    test('decodeTokenPayload correctly decodes valid JWT payload', () {
      final token = createMockJwt({
        'sub': 'user_12345',
        'role': 'student',
        'email': 'student@gsfcuniversity.ac.in',
      });

      final decoded = JwtDecoderUtil.decodeTokenPayload(token);
      expect(decoded, isNotNull);
      expect(decoded!['sub'], 'user_12345');
      expect(decoded['role'], 'student');
      expect(decoded['email'], 'student@gsfcuniversity.ac.in');
    });

    test('decodeTokenPayload handles different base64url padding lengths', () {
      // Test payload variations to trigger padding cases (payload.length % 4 == 2 or 3)
      final tokenCase1 = createMockJwt({'a': 'b'});
      final tokenCase2 = createMockJwt({'test_key': 'test_value_with_longer_payload'});

      expect(JwtDecoderUtil.decodeTokenPayload(tokenCase1), isNotNull);
      expect(JwtDecoderUtil.decodeTokenPayload(tokenCase2), isNotNull);
    });

    test('decodeTokenPayload returns null on invalid or malformed tokens', () {
      expect(JwtDecoderUtil.decodeTokenPayload('invalid_token_string'), isNull);
      expect(JwtDecoderUtil.decodeTokenPayload('part1.part2'), isNull);
      expect(JwtDecoderUtil.decodeTokenPayload(r'part1.not_valid_base64_!@#$.part3'), isNull);
    });

    test('getRoleFromToken extracts role correctly', () {
      final studentToken = createMockJwt({'role': 'student'});
      final recruiterToken = createMockJwt({'role': 'recruiter'});
      final emptyToken = createMockJwt({});

      expect(JwtDecoderUtil.getRoleFromToken(studentToken), 'student');
      expect(JwtDecoderUtil.getRoleFromToken(recruiterToken), 'recruiter');
      expect(JwtDecoderUtil.getRoleFromToken(emptyToken), isNull);
      expect(JwtDecoderUtil.getRoleFromToken('garbage'), isNull);
    });

    test('getUserIdFromToken extracts subject (sub) correctly', () {
      final token = createMockJwt({'sub': 'student_user_abc'});
      expect(JwtDecoderUtil.getUserIdFromToken(token), 'student_user_abc');
      expect(JwtDecoderUtil.getUserIdFromToken('garbage'), isNull);
    });

    test('isTokenExpired returns true if token is expired', () {
      final pastEpoch = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 3600; // 1 hour ago
      final expiredToken = createMockJwt({'exp': pastEpoch});

      expect(JwtDecoderUtil.isTokenExpired(expiredToken), isTrue);
    });

    test('isTokenExpired returns false if token is active and valid in future', () {
      final futureEpoch = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600; // 1 hour ahead
      final activeToken = createMockJwt({'exp': futureEpoch});

      expect(JwtDecoderUtil.isTokenExpired(activeToken), isFalse);
    });

    test('isTokenExpired defaults to true on missing exp claim or malformed token', () {
      final noExpToken = createMockJwt({'sub': 'test'});
      expect(JwtDecoderUtil.isTokenExpired(noExpToken), isTrue);
      expect(JwtDecoderUtil.isTokenExpired('malformed'), isTrue);
    });
  });
}
