import 'dart:io' show HttpClient;
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import '../services/token_storage_service.dart';
import 'cert_pinning_config.dart';

class ApiClient {
  static final ApiClient instance = ApiClient._internal();
  late final Dio dio;
  final TokenStorageService _tokenStorage = TokenStorageService();
  void Function()? onForceLogout;

  ApiClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: _getBaseUrl(),
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Apply TLS Certificate Pinning on native mobile/desktop platforms (bypass on Web)
    if (!kIsWeb) {
      if (dio.httpClientAdapter is IOHttpClientAdapter) {
        (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
          final client = HttpClient();
          client.badCertificateCallback = (cert, host, port) {
            return CertPinningConfig.validateCertificate(cert, host, port);
          };
          return client;
        };
      }
    }

    // Attach Dio Interceptor
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Attach persistent Device ID header
          final deviceId = await _tokenStorage.getOrCreateDeviceId();
          options.headers['X-Device-ID'] = deviceId;

          // Attach Bearer Access Token if present
          final accessToken = await _tokenStorage.getAccessToken();
          if (accessToken != null && accessToken.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $accessToken';
          }

          // Bypass ngrok free browser warning interstitial
          options.headers['ngrok-skip-browser-warning'] = 'true';

          return handler.next(options);
        },
        onError: (error, handler) async {
          // Handle 401 Unauthorized -> Attempt Silent Refresh
          if (error.response?.statusCode == 401) {
            final path = error.requestOptions.path;
            if (!path.contains('/auth/login') && !path.contains('/auth/refresh')) {
              final isRefreshed = await attemptSilentRefresh();
              if (isRefreshed) {
                // Retry original request with new token
                final newAccessToken = await _tokenStorage.getAccessToken();
                error.requestOptions.headers['Authorization'] = 'Bearer $newAccessToken';
                try {
                  final response = await dio.fetch(error.requestOptions);
                  return handler.resolve(response);
                } catch (retryError) {
                  return handler.reject(error);
                }
              } else {
                // Silent refresh failed -> Force Logout
                await _tokenStorage.clearTokens();
                onForceLogout?.call();
              }
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  String _getBaseUrl() {
    // 1. Check compile-time environment variable: --dart-define=API_URL=https://...
    const envUrl = String.fromEnvironment('API_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    // 2. Active Cloud ngrok tunnel for reliable real-device connectivity without adb reverse drops
    return 'https://unrecorded-unpretended-loretta.ngrok-free.dev';
  }

  Future<bool> attemptSilentRefresh() async {
    try {
      final refreshToken = await _tokenStorage.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) return false;

      final response = await dio.post(
        '/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(headers: {'Authorization': ''}),
      );

      if (response.statusCode == 200 && response.data != null) {
        final newAccessToken = response.data['access_token'];
        final newRefreshToken = response.data['refresh_token'];
        if (newAccessToken != null && newRefreshToken != null) {
          await _tokenStorage.saveAccessToken(newAccessToken);
          await _tokenStorage.saveRefreshToken(newRefreshToken);
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}