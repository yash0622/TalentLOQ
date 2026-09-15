import 'package:flutter_test/flutter_test.dart';
import 'package:talentloq/utils/validators.dart';

void main() {
  group('Validators - Unit Tests', () {
    group('validateRequired', () {
      test('returns error when value is null or empty', () {
        expect(Validators.validateRequired(null), 'This field is required');
        expect(Validators.validateRequired(''), 'This field is required');
        expect(Validators.validateRequired('   '), 'This field is required');
      });

      test('custom fieldName is reflected in error message', () {
        expect(Validators.validateRequired('', 'Phone number'), 'Phone number is required');
      });

      test('returns null when valid value is provided', () {
        expect(Validators.validateRequired('valid input'), isNull);
      });
    });

    group('validateFullName', () {
      test('returns error when null or empty', () {
        expect(Validators.validateFullName(null), 'Full Name is required');
        expect(Validators.validateFullName(''), 'Full Name is required');
        expect(Validators.validateFullName('   '), 'Full Name is required');
      });

      test('returns error when shorter than 2 characters', () {
        expect(Validators.validateFullName('A'), 'Full name must be at least 2 characters long');
      });

      test('returns null for valid full names', () {
        expect(Validators.validateFullName('John Doe'), isNull);
        expect(Validators.validateFullName('Jane'), isNull);
      });
    });

    group('validateEmail', () {
      test('returns error for empty or whitespace string', () {
        expect(Validators.validateEmail(null), 'Email address is required');
        expect(Validators.validateEmail(''), 'Email address is required');
        expect(Validators.validateEmail('   '), 'Email address is required');
      });

      test('returns error for malformed emails', () {
        expect(Validators.validateEmail('plainaddress'), 'Please enter a valid email address');
        expect(Validators.validateEmail('@missingusername.com'), 'Please enter a valid email address');
        expect(Validators.validateEmail('username@.com'), 'Please enter a valid email address');
      });

      test('returns null for valid standard emails', () {
        expect(Validators.validateEmail('user@example.com'), isNull);
        expect(Validators.validateEmail('first.last@domain.co.in'), isNull);
      });
    });

    group('validateStudentEmail', () {
      test('rejects non-GSFC emails', () {
        expect(
          Validators.validateStudentEmail('student@gmail.com'),
          'Only GSFC University student emails (@gsfcuniversity.ac.in) are allowed',
        );
        expect(
          Validators.validateStudentEmail('student@yahoo.com'),
          'Only GSFC University student emails (@gsfcuniversity.ac.in) are allowed',
        );
      });

      test('accepts valid GSFC University emails', () {
        expect(Validators.validateStudentEmail('student123@gsfcuniversity.ac.in'), isNull);
        expect(Validators.validateStudentEmail('CS.2023.101@GSFCUNIVERSITY.AC.IN'), isNull);
      });
    });

    group('validatePassword & getPasswordStrengthScore', () {
      test('returns error for passwords violating complexity requirements', () {
        expect(Validators.validatePassword(null), 'Password is required');
        expect(Validators.validatePassword(''), 'Password is required');
        expect(Validators.validatePassword('Short1!'), 'Password must be at least 8 characters long');
        expect(Validators.validatePassword('alllowercase1!'), 'Password must contain at least one uppercase letter');
        expect(Validators.validatePassword('ALLUPPERCASE1!'), 'Password must contain at least one lowercase letter');
        expect(Validators.validatePassword('NoDigitsHere!'), 'Password must contain at least one number');
        expect(Validators.validatePassword('NoSpecialChar123'), 'Password must contain at least one special character (!@#\$%^&*)');
      });

      test('returns null for strong valid password', () {
        expect(Validators.validatePassword('SecureP@ssw0rd!'), isNull);
      });

      test('calculates correct password strength score', () {
        expect(Validators.getPasswordStrengthScore(''), 0);
        expect(Validators.getPasswordStrengthScore('weak'), 0);
        expect(Validators.getPasswordStrengthScore('password123'), 2); // >=8, number
        expect(Validators.getPasswordStrengthScore('Password123'), 3); // >=8, upper, number
        expect(Validators.getPasswordStrengthScore('P@ssword123'), 4); // >=8, upper, number, special
      });
    });

    group('validateCgpa', () {
      test('validates required and numeric bounds', () {
        expect(Validators.validateCgpa(null), 'CGPA is required');
        expect(Validators.validateCgpa(''), 'CGPA is required');
        expect(Validators.validateCgpa('not_a_number'), 'CGPA must be between 0.0 and 10.0');
        expect(Validators.validateCgpa('-1.0'), 'CGPA must be between 0.0 and 10.0');
        expect(Validators.validateCgpa('10.5'), 'CGPA must be between 0.0 and 10.0');
      });

      test('accepts valid CGPA within 0.0 - 10.0', () {
        expect(Validators.validateCgpa('0.0'), isNull);
        expect(Validators.validateCgpa('8.75'), isNull);
        expect(Validators.validateCgpa('10.0'), isNull);
      });
    });

    group('validateBacklog', () {
      test('rejects negative or invalid input', () {
        expect(Validators.validateBacklog(null, 'Active Backlogs'), 'Active Backlogs is required');
        expect(Validators.validateBacklog('-2', 'Active Backlogs'), 'Please enter a valid number (>= 0)');
        expect(Validators.validateBacklog('abc', 'Closed Backlogs'), 'Please enter a valid number (>= 0)');
      });

      test('accepts zero and positive integers', () {
        expect(Validators.validateBacklog('0', 'Active Backlogs'), isNull);
        expect(Validators.validateBacklog('3', 'Active Backlogs'), isNull);
      });
    });

    group('sanitizeText', () {
      test('strips script tags and malicious HTML', () {
        expect(Validators.sanitizeText(''), '');
        expect(
          Validators.sanitizeText('Hello <script>alert("XSS")</script>World'),
          'Hello World',
        );
        expect(
          Validators.sanitizeText('<b>Bold</b> and <i>italic</i>'),
          'Bold and italic',
        );
      });
    });
  });
}
