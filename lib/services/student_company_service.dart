import 'package:dio/dio.dart';
import '../network/api_client.dart';

class StudentCompanyService {
  final ApiClient _apiClient = ApiClient.instance;

  // 1. Fetch Published Companies
  Future<List<dynamic>> getPublishedCompanies() async {
    try {
      final response = await _apiClient.dio.get('/companies');
      if (response.statusCode == 200) {
        return response.data as List<dynamic>;
      }
    } catch (_) {}
    return [];
  }

  // 2. Fetch Company Detail
  Future<Map<String, dynamic>?> getCompanyDetail(String listingId) async {
    try {
      final response = await _apiClient.dio.get('/companies/$listingId');
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return null;
  }

  // 3. Apply to Company Listing
  Future<Map<String, dynamic>> applyToCompanyListing(String listingId) async {
    try {
      final response = await _apiClient.dio.post('/companies/$listingId/apply');
      if (response.statusCode == 201) {
        return {'success': true, 'data': response.data};
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final detail = e.response?.data is Map ? e.response?.data['detail']?.toString() : null;

      if (statusCode == 400 && (detail?.contains('resume') ?? false)) {
        return {
          'success': false,
          'no_resume': true,
          'message': detail ?? 'No uploaded resume found. Please upload a resume first.',
        };
      }
      if (statusCode == 409) {
        return {
          'success': false,
          'conflict': true,
          'message': detail ?? 'You have already applied to this company drive.',
        };
      }
      return {
        'success': false,
        'message': detail ?? 'Failed to submit application. Please try again.',
      };
    } catch (_) {}

    return {
      'success': false,
      'message': 'Failed to submit application. Please try again.',
    };
  }
}
