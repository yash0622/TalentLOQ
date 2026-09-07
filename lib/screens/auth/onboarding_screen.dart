import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/validators.dart';
import 'otp_verification_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onLoginComplete;

  const OnboardingScreen({super.key, required this.onLoginComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  int _selectedRoleIndex = 0; // 0: Student, 1: Recruiter
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _successMessage;
  DateTime? _lastBackPressTime;

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _educationController = TextEditingController();
  final _cgpaController = TextEditingController();
  final _activeBacklogsController = TextEditingController();
  final _closedBacklogsController = TextEditingController();
  final _skillInputController = TextEditingController();

  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _educationController.dispose();
    _cgpaController.dispose();
    _activeBacklogsController.dispose();
    _closedBacklogsController.dispose();
    _skillInputController.dispose();
    super.dispose();
  }

  Future<void> _handleAuthSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      if (_isSignUp) {
        if (_selectedRoleIndex == 1) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Recruiter accounts cannot self-register. Please use the reserved recruiter login.';
          });
          return;
        }

        final fullName = _fullNameController.text.trim();
        final registered = await _authService.register(
          fullName: fullName,
          email: email,
          password: password,
        );

        if (registered) {
          setState(() {
            _isSignUp = false;
            _passwordController.clear();
            _successMessage =
                'Registration successful! Please sign in with your password.';
            _errorMessage = null;
          });
        }
      } else {
        final result = await _authService.login(
          email: email,
          password: password,
        );

        if (result.status == AuthStatus.otpRequired &&
            result.tempToken != null) {
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => OtpVerificationScreen(
                  tempToken: result.tempToken!,
                  onVerificationSuccess: () {
                    Navigator.of(context).pop();
                    widget.onLoginComplete();
                  },
                  onBackToLogin: () => Navigator.of(context).pop(),
                ),
              ),
            );
          }
        } else if (result.status == AuthStatus.untrustedDeviceBlocked) {
          setState(() {
            _errorMessage =
                result.message ??
                'Unrecognized device. Check your email for a verification link.';
          });
        } else if (result.status == AuthStatus.success) {
          widget.onLoginComplete();
        } else {
          setState(() {
            _errorMessage = result.message ?? 'Authentication failed';
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildPasswordStrengthIndicator() {
    final pwd = _passwordController.text;
    if (pwd.isEmpty) return const SizedBox.shrink();

    final score = Validators.getPasswordStrengthScore(pwd);
    Color color = Colors.red;
    String label = 'Weak';
    if (score == 2) {
      color = Colors.orange;
      label = 'Fair';
    } else if (score == 3) {
      color = Colors.blue;
      label = 'Good';
    } else if (score >= 4) {
      color = Colors.green;
      label = 'Strong';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (score + 1) / 5.0,
                color: color,
                backgroundColor: Colors.grey.withValues(alpha: 0.2),
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isSignUp) {
          setState(() {
            _isSignUp = false;
            _errorMessage = null;
            _successMessage = null;
          });
          return;
        }
        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Press back again to exit TalentLOQ'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF0F0E17)
            : const Color(0xFFF6F8FC),
        body: Stack(
          children: [
          // Ambient Decorative Gradient Glows
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark ? const Color(0xFF6366F1) : const Color(0xFF818CF8))
                        .withValues(alpha: 0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -60,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (isDark ? const Color(0xFF4F46E5) : const Color(0xFF6366F1))
                        .withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main Scrollable Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Top Header / Branding
                        Center(
                          child: Column(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF6366F1),
                                      Color(0xFF4338CA),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF4F46E5,
                                      ).withValues(alpha: 0.35),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.insights_rounded,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Talent',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.5,
                                          color: isDark
                                              ? Colors.white
                                              : const Color(0xFF0F172A),
                                        ),
                                  ),
                                  Text(
                                    'LOQ',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.5,
                                          color: const Color(0xFF4F46E5),
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Campus Placement & Career Matcher',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Role Selector Toggle (Student vs Recruiter)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1E1D2A)
                                : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildRoleButton(
                                  title: 'Student',
                                  icon: Icons.school_rounded,
                                  isSelected: _selectedRoleIndex == 0,
                                  isDark: isDark,
                                  onTap: () {
                                    setState(() {
                                      _selectedRoleIndex = 0;
                                      _errorMessage = null;
                                      _successMessage = null;
                                    });
                                  },
                                ),
                              ),
                              Expanded(
                                child: _buildRoleButton(
                                  title: 'Recruiter',
                                  icon: Icons.business_center_rounded,
                                  isSelected: _selectedRoleIndex == 1,
                                  isDark: isDark,
                                  onTap: () {
                                    setState(() {
                                      _selectedRoleIndex = 1;
                                      _isSignUp =
                                          false; // Recruiters cannot sign up
                                      _errorMessage = null;
                                      _successMessage = null;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Form Container Card
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 24,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF181724)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF2A283B)
                                  : const Color(0xFFEDF2F7),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.3 : 0.04,
                                ),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Card Header Title
                              Text(
                                _isSignUp
                                    ? 'Create Student Account'
                                    : (_selectedRoleIndex == 1
                                          ? 'Recruiter Sign In'
                                          : 'Student Sign In'),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isSignUp
                                    ? 'Register with your official @gsfcuniversity.ac.in ID'
                                    : (_selectedRoleIndex == 1
                                          ? 'Access university drives & applicant pipeline'
                                          : 'GSFC University Student Sign In (@gsfcuniversity.ac.in)'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(height: 18),

                              // Success Alert Banner
                              if (_successMessage != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.success.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.check_circle_rounded,
                                        color: AppColors.success,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _successMessage!,
                                          style: const TextStyle(
                                            color: AppColors.success,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],

                              // Error Alert Banner
                              if (_errorMessage != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.error.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: AppColors.error,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: const TextStyle(
                                            color: AppColors.error,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],

                              // Full Name (Only for Registration)
                              if (_isSignUp) ...[
                                _buildFieldLabel('Full Name *', isDark),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _fullNameController,
                                  textCapitalization: TextCapitalization.words,
                                  validator: (v) => Validators.validateRequired(
                                    v,
                                    'Full Name',
                                  ),
                                  style: const TextStyle(fontSize: 14),
                                  decoration: _inputDecoration(
                                    hint: 'Enter Your Full Name',
                                    icon: Icons.person_outline_rounded,
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],

                              // Email Address Field
                              _buildFieldLabel('Email Address *', isDark),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                validator: (v) {
                                  if (_selectedRoleIndex == 0) {
                                    return Validators.validateStudentEmail(v);
                                  }
                                  return Validators.validateRequired(
                                    v,
                                    'Recruiter Email',
                                  );
                                },
                                style: const TextStyle(fontSize: 14),
                                decoration: _inputDecoration(
                                  hint: _selectedRoleIndex == 0
                                      ? 'student@gsfcuniversity.ac.in'
                                      : 'recruiter@company.com',
                                  icon: Icons.mail_outline_rounded,
                                  isDark: isDark,
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Password Field
                              _buildFieldLabel('Password *', isDark),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                onChanged: _isSignUp
                                    ? (_) => setState(() {})
                                    : null,
                                validator: _isSignUp
                                    ? Validators.validatePassword
                                    : (v) => Validators.validateRequired(
                                        v,
                                        'Password',
                                      ),
                                style: const TextStyle(fontSize: 14),
                                decoration: _inputDecoration(
                                  hint: 'Enter your password',
                                  icon: Icons.lock_outline_rounded,
                                  isDark: isDark,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 18,
                                      color: isDark
                                          ? const Color(0xFF94A3B8)
                                          : const Color(0xFF64748B),
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),
                              ),
                              if (_isSignUp) _buildPasswordStrengthIndicator(),
                              const SizedBox(height: 14),

                              // Automatic Document Verification Notice
                              if (_isSignUp) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF4F46E5,
                                    ).withValues(alpha: isDark ? 0.15 : 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF4F46E5,
                                      ).withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.verified_user_outlined,
                                        size: 20,
                                        color: Color(0xFF4F46E5),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'Academic credentials (Degree, CGPA, backlogs & skills) are verified automatically via document upload after signing in.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark
                                                ? const Color(0xFFCBD5E1)
                                                : const Color(0xFF475569),
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],

                              const SizedBox(height: 10),

                              // Primary Action Submit Button with Modern Gradient & Glow
                              Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF6366F1),
                                      Color(0xFF4F46E5),
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF4F46E5,
                                      ).withValues(alpha: 0.35),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: _isLoading
                                        ? null
                                        : _handleAuthSubmit,
                                    child: Center(
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.5,
                                              ),
                                            )
                                          : Text(
                                              _isSignUp
                                                  ? 'Register Student Account'
                                                  : (_selectedRoleIndex == 1
                                                        ? 'Proceed to 2-Step Verification'
                                                        : 'Sign In to TalentLOQ'),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Switch between Sign In / Register
                        if (_selectedRoleIndex == 0)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _isSignUp
                                    ? 'Already have an account?'
                                    : 'New student?',
                                style: TextStyle(
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF64748B),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _isSignUp = !_isSignUp;
                                    _errorMessage = null;
                                    _successMessage = null;
                                  });
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                child: Text(
                                  _isSignUp ? 'Sign In' : 'Register Now',
                                  style: const TextStyle(
                                    color: Color(0xFF4F46E5),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),

                        const SizedBox(height: 10),
                        // University Placement Cell Footnote
                        Center(
                          child: Text(
                            'GSFC University Placement Cell • Secure Career Portal',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? const Color(0xFF64748B)
                                  : const Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildRoleButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF2E2D3E) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? const Color(0xFF4F46E5)
                  : (isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Colors.white : const Color(0xFF0F172A))
                    : (isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label, bool isDark) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    required bool isDark,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 13,
        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
      ),
      prefixIcon: Icon(
        icon,
        size: 18,
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark ? const Color(0xFF1E1D2C) : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF2E2D3E) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF2E2D3E) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
      ),
    );
  }
}
