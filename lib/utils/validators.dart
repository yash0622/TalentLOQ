class Validators {
  /// Validates generic required field
  static String? validateRequired(String? value, [String fieldName = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  /// Validates Full Name field
  static String? validateFullName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Full Name is required';
    }
    if (value.trim().length < 2) {
      return 'Full name must be at least 2 characters long';
    }
    return null;
  }

  /// Validates general email address format
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email address is required';
    }
    final email = value.trim();
    final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
    if (!emailRegex.hasMatch(email)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  /// Validates student email address - MUST belong to GSFC University (@gsfcuniversity.ac.in)
  static String? validateStudentEmail(String? value) {
    final basicError = validateEmail(value);
    if (basicError != null) return basicError;

    final email = value!.trim().toLowerCase();
    if (!email.endsWith('@gsfcuniversity.ac.in') && !email.contains('gsfcuniversity')) {
      return 'Only GSFC University student emails (@gsfcuniversity.ac.in) are allowed';
    }
    return null;
  }

  /// Validates password for registration
  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters long';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
      return 'Password must contain at least one special character (!@#\$%^&*)';
    }
    return null;
  }

  /// Simple password validation for Sign In form (only checks non-empty)
  static String? validateLoginPassword(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Password is required';
    }
    return null;
  }

  /// Calculates password strength score from 0 (very weak) to 4 (strong)
  static int getPasswordStrengthScore(String password) {
    if (password.isEmpty) return 0;
    int score = 0;
    if (password.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) score++;
    return score;
  }

  /// Validates CGPA score (0.0 to 10.0)
  static String? validateCgpa(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'CGPA is required';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed < 0.0 || parsed > 10.0) {
      return 'CGPA must be between 0.0 and 10.0';
    }
    return null;
  }

  /// Validates Education / Degree field
  static String? validateEducation(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Education / Degree is required';
    }
    return null;
  }

  /// Validates Backlog field (must be non-negative integer)
  static String? validateBacklog(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 0) {
      return 'Please enter a valid number (>= 0)';
    }
    return null;
  }

  /// Client-side HTML/Script tag sanitization before rendering
  static String sanitizeText(String text) {
    if (text.isEmpty) return '';
    // Strip script tags
    String clean = text.replaceAll(RegExp(r'<script.*?>.*?</script>', caseSensitive: false, dotAll: true), '');
    // Strip all HTML tags
    clean = clean.replaceAll(RegExp(r'<[^>]*>'), '');
    return clean;
  }
}
