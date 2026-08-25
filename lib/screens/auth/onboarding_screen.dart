import 'package:flutter/material.dart';
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

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _selectedRoleIndex = 0; // 0: Job Seeker/Student, 1: Recruiter
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _successMessage;

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _educationController = TextEditingController();
  final _cgpaController = TextEditingController();
  final _activeBacklogsController = TextEditingController();
  final _closedBacklogsController = TextEditingController();
  final _skillInputController = TextEditingController();
  final List<String> _skillsList = [];

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

  void _addSkill(String value) {
    final clean = value.trim();
    if (clean.isNotEmpty && !_skillsList.contains(clean)) {
      setState(() {
        _skillsList.add(clean);
        _skillInputController.clear();
      });
    }
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
        // Registration Flow (Student Only)
        if (_selectedRoleIndex == 1) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Recruiter accounts cannot self-register. Please use the reserved recruiter login.';
          });
          return;
        }

        final fullName = _fullNameController.text.trim();
        final education = _educationController.text.trim();
        final cgpa = double.tryParse(_cgpaController.text.trim()) ?? 0.0;
        final activeBacklogs = int.tryParse(_activeBacklogsController.text.trim()) ?? 0;
        final closedBacklogs = int.tryParse(_closedBacklogsController.text.trim()) ?? 0;

        final skills = List<String>.from(_skillsList);
        final pendingSkill = _skillInputController.text.trim();
        if (pendingSkill.isNotEmpty && !skills.contains(pendingSkill)) {
          skills.add(pendingSkill);
        }

        if (skills.isEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Please add at least one skill to complete registration.';
          });
          return;
        }

        final registered = await _authService.register(
          fullName: fullName,
          email: email,
          password: password,
          education: education,
          cgpa: cgpa,
          activeBacklogs: activeBacklogs,
          closedBacklogs: closedBacklogs,
          skills: skills,
        );

        if (registered) {
          setState(() {
            _isSignUp = false;
            _passwordController.clear();
            _successMessage = 'Registration successful! Please sign in with your password.';
            _errorMessage = null;
          });
        }
      } else {
        // Login Flow (Handles Student Direct Login & Recruiter 2-Step OTP Flow)
        final result = await _authService.login(email: email, password: password);

        if (result.status == AuthStatus.otpRequired && result.tempToken != null) {
          // Navigate to 2-Step OTP Entry Screen for Recruiter
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
            _errorMessage = result.message ?? 'Unrecognized device. Check your email for a device verification link.';
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
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (score + 1) / 5.0,
                color: color,
                backgroundColor: Colors.grey.shade300,
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isSmallScreen = screenWidth < 380;
    final horizontalPadding = isSmallScreen ? 16.0 : 24.0;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkPrimaryContainer
                                : AppColors.lightPrimary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.insights_rounded,
                            color: Colors.white,
                            size: isSmallScreen ? 26 : 32,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'TalentLOQ',
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontSize: isSmallScreen ? 24 : 28,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Campus Placement Tracker & Placement Matcher',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: isSmallScreen ? 12 : 14,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Role Selection Pills
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurfaceContainerLow
                            : AppColors.lightSurfaceContainer,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedRoleIndex = 0;
                                  _errorMessage = null;
                                  _emailController.clear();
                                  _passwordController.clear();
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _selectedRoleIndex == 0
                                      ? (isDark
                                          ? AppColors.darkPrimaryContainer
                                          : AppColors.lightPrimary)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Text(
                                  'Student',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: isSmallScreen ? 12 : 14,
                                    color: _selectedRoleIndex == 0
                                        ? Colors.white
                                        : (isDark
                                            ? AppColors.darkTextSecondary
                                            : AppColors.lightTextSecondary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedRoleIndex = 1;
                                  _isSignUp = false; // Recruiter login only
                                  _errorMessage = null;
                                  _emailController.clear();
                                  _passwordController.clear();
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _selectedRoleIndex == 1
                                      ? (isDark
                                          ? AppColors.darkPrimaryContainer
                                          : AppColors.lightPrimary)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: Text(
                                  'Recruiter',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: isSmallScreen ? 12 : 14,
                                    color: _selectedRoleIndex == 1
                                        ? Colors.white
                                        : (isDark
                                            ? AppColors.darkTextSecondary
                                            : AppColors.lightTextSecondary),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Auth Card Container
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _isSignUp
                                  ? 'Student Registration'
                                  : (_selectedRoleIndex == 1 ? 'Recruiter 2-Step Login' : 'Student Sign In'),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontSize: isSmallScreen ? 18 : 20,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isSignUp
                                  ? 'Restricted to GSFC University students (@gsfcuniversity.ac.in).'
                                  : (_selectedRoleIndex == 1
                                      ? 'Requires password + 6-digit OTP verification.'
                                      : 'GSFC University Student Sign In (@gsfcuniversity.ac.in).'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: isSmallScreen ? 11 : 12,
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Success Message Banner
                            if (_successMessage != null)
                              Container(
                                padding: const EdgeInsets.all(10),
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: AppColors.successLightBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.success),
                                ),
                                child: Text(
                                  _successMessage!,
                                  style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),

                            // Error Message Banner
                            if (_errorMessage != null)
                              Container(
                                padding: const EdgeInsets.all(10),
                                margin: const EdgeInsets.only(bottom: 14),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.error),
                                ),
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                                ),
                              ),

                            // Full Name Field (Registration Mode Only)
                            if (_isSignUp) ...[
                              Text(
                                'Full Name *',
                                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _fullNameController,
                                validator: Validators.validateFullName,
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'Enter your full name',
                                  prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],

                            // Email Field
                            Text(
                              'Email Address',
                              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                             TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              validator: _selectedRoleIndex == 0 ? Validators.validateStudentEmail : Validators.validateEmail,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: 'Enter your email address',
                                prefixIcon: Icon(Icons.email_outlined, size: 18),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Password Field
                            Text(
                              'Password',
                              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              validator: _isSignUp ? Validators.validatePassword : Validators.validateLoginPassword,
                              onChanged: (_) => setState(() {}),
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Enter your password',
                                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                              ),
                            ),
                            if (_isSignUp) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Must contain at least 8 characters, 1 uppercase, 1 lowercase, 1 number & 1 special character (!@#\$%^&*).',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                              ),
                            ],

                            // Password Strength Meter
                            if (_isSignUp) _buildPasswordStrengthIndicator(),
                            const SizedBox(height: 14),

                            // Additional Student Registration Fields
                            if (_isSignUp && _selectedRoleIndex == 0) ...[
                              Text(
                                'Education / Degree *',
                                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _educationController,
                                validator: Validators.validateEducation,
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'e.g. B.Tech Computer Science',
                                  prefixIcon: Icon(Icons.school_outlined, size: 18),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Current CGPA
                              Text(
                                'Current CGPA *',
                                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _cgpaController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                validator: Validators.validateCgpa,
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'e.g. 8.5',
                                  prefixIcon: Icon(Icons.grade_outlined, size: 18),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Backlog Fields Row: Active Backlog & Closed Backlog
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Current Backlog *',
                                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 6),
                                        TextFormField(
                                          controller: _activeBacklogsController,
                                          keyboardType: TextInputType.number,
                                          validator: (v) => Validators.validateBacklog(v, 'Current Backlog'),
                                          style: const TextStyle(fontSize: 13),
                                          decoration: const InputDecoration(
                                            hintText: '0',
                                            prefixIcon: Icon(Icons.warning_amber_rounded, size: 18),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Closed Backlog *',
                                          style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 6),
                                        TextFormField(
                                          controller: _closedBacklogsController,
                                          keyboardType: TextInputType.number,
                                          validator: (v) => Validators.validateBacklog(v, 'Closed Backlog'),
                                          style: const TextStyle(fontSize: 13),
                                          decoration: const InputDecoration(
                                            hintText: '0',
                                            prefixIcon: Icon(Icons.check_circle_outline_rounded, size: 18),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Dynamic Skills Chips Entry Field (Press Enter to Add)
                              Text(
                                'Skills (Press Enter after each skill) *',
                                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _skillInputController,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: _addSkill,
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Type skill & press Enter',
                                  prefixIcon: const Icon(Icons.code_rounded, size: 18),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.lightPrimary, size: 18),
                                    onPressed: () => _addSkill(_skillInputController.text),
                                    tooltip: 'Add Skill',
                                  ),
                                ),
                              ),
                              if (_skillsList.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _skillsList.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final skill = entry.value;
                                    return InputChip(
                                      label: Text(skill),
                                      labelStyle: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.white : AppColors.lightPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      backgroundColor: isDark
                                          ? AppColors.darkPrimaryContainer
                                          : AppColors.primaryLightBg,
                                      deleteIconColor: isDark ? Colors.white70 : AppColors.lightPrimary,
                                      onDeleted: () {
                                        setState(() {
                                          _skillsList.removeAt(index);
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                              const SizedBox(height: 18),
                            ],

                            // Action Button
                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleAuthSubmit,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : Text(
                                      _isSignUp
                                          ? 'Register Student Account'
                                          : (_selectedRoleIndex == 1 ? 'Proceed to 2-Step Verification' : 'Sign In to TalentLOQ'),
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 14 : 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Registration Toggle (Student only)
                    if (_selectedRoleIndex == 0)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isSignUp ? 'Already registered?' : "New student?",
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: isSmallScreen ? 12 : 14,
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _isSignUp = !_isSignUp;
                              _errorMessage = null;
                            }),
                            child: Text(
                              _isSignUp ? 'Sign In' : 'Register Now',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: isSmallScreen ? 12 : 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
