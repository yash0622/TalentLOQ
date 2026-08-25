import 'package:flutter/material.dart';
import '../services/token_storage_service.dart';
import '../utils/jwt_decoder_util.dart';

class RoleBasedRouter {
  final TokenStorageService _tokenStorage = TokenStorageService();

  /// Resolves initial user destination screen based on valid JWT role claim
  Future<String> resolveInitialRoute() async {
    final accessToken = await _tokenStorage.getAccessToken();

    if (accessToken == null || accessToken.isEmpty) {
      return '/onboarding';
    }

    if (JwtDecoderUtil.isTokenExpired(accessToken)) {
      // Token expired -> User needs re-authentication
      return '/onboarding';
    }

    final role = JwtDecoderUtil.getRoleFromToken(accessToken);
    if (role == 'recruiter') {
      return '/recruiter-portal';
    } else {
      return '/student-dashboard';
    }
  }

  /// Builds appropriate main widget based on decoded role claim
  Widget buildRoleBasedHome({
    required String role,
    required Widget studentScreen,
    required Widget recruiterScreen,
  }) {
    if (role == 'recruiter') {
      return recruiterScreen;
    }
    return studentScreen;
  }
}
