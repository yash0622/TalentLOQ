import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../network/api_client.dart';
import '../controllers/paging_controller.dart';
import 'application_visibility_state.dart';

class DriveService {
  final ApiClient _apiClient = ApiClient.instance;

  // 1. Create Placement Drive (Multipart FormData)
  Future<bool> createDrive(Map<String, dynamic> data, String? pdfFilePath) async {
    try {
      final mapData = Map<String, dynamic>.from(data);

      if (pdfFilePath != null && pdfFilePath.isNotEmpty) {
        mapData['pdf'] = await MultipartFile.fromFile(
          pdfFilePath,
          filename: pdfFilePath.split('/').last.split('\\').last,
        );
      }

      final formData = FormData.fromMap(mapData);
      final response = await _apiClient.dio.post(
        '/recruiter/drives',
        data: formData,
      );
      if (response.statusCode == 201) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // 2. Edit Placement Drive
  Future<bool> editDrive(String driveId, Map<String, dynamic> updateData) async {
    try {
      final response = await _apiClient.dio.patch(
        '/recruiter/drives/$driveId',
        data: updateData,
      );
      if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // 3. Publish Placement Drive
  Future<bool> publishDrive(String driveId, {String targetAudience = "all"}) async {
    try {
      final response = await _apiClient.dio.post(
        '/recruiter/drives/$driveId/publish?target_audience=$targetAudience',
      );
      if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // 4. Fetch Recruiter Placement Drives
  Future<List<dynamic>> getRecruiterDrives() async {
    try {
      final response = await _apiClient.dio.get('/recruiter/drives');
      if (response.statusCode == 200) {
        if (response.data is Map<String, dynamic> && response.data['items'] != null) {
          return response.data['items'] as List<dynamic>;
        } else if (response.data is List) {
          return response.data as List<dynamic>;
        }
      }
    } catch (_) {}
    return [];
  }

  Future<PaginatedResponse<Map<String, dynamic>>> getRecruiterDrivesPaginated({int page = 1, int limit = 20}) async {
    try {
      final response = await _apiClient.dio.get('/recruiter/drives?page=$page&limit=$limit');
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return PaginatedResponse<Map<String, dynamic>>.fromJson(
          response.data as Map<String, dynamic>,
          (item) => Map<String, dynamic>.from(item as Map),
        );
      }
    } catch (_) {}
    return PaginatedResponse<Map<String, dynamic>>(
      items: [],
      page: page,
      limit: limit,
      totalCount: 0,
      hasMore: false,
    );
  }

  // 5. Fetch Applicants for a Drive
  Future<List<dynamic>> getDriveApplicants(String driveId) async {
    try {
      final response = await _apiClient.dio.get('/recruiter/drives/$driveId/applicants');
      if (response.statusCode == 200) {
        if (response.data is Map<String, dynamic> && response.data['items'] != null) {
          return response.data['items'] as List<dynamic>;
        } else if (response.data is List) {
          return response.data as List<dynamic>;
        }
      }
    } catch (_) {}
    return [];
  }

  Future<PaginatedResponse<Map<String, dynamic>>> getDriveApplicantsPaginated(String driveId, {int page = 1, int limit = 20}) async {
    try {
      final response = await _apiClient.dio.get('/recruiter/drives/$driveId/applicants?page=$page&limit=$limit');
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return PaginatedResponse<Map<String, dynamic>>.fromJson(
          response.data as Map<String, dynamic>,
          (item) => Map<String, dynamic>.from(item as Map),
        );
      }
    } catch (_) {}
    return PaginatedResponse<Map<String, dynamic>>(
      items: [],
      page: page,
      limit: limit,
      totalCount: 0,
      hasMore: false,
    );
  }

  // 6. Record Candidate Round Result
  Future<Map<String, dynamic>?> updateCandidateRound(
    String driveId,
    String studentId,
    String result, {
    String? customMessage,
  }) async {
    try {
      final payload = <String, dynamic>{'result': result};
      if (customMessage != null && customMessage.trim().isNotEmpty) {
        payload['custom_message'] = customMessage.trim();
      }
      final response = await _apiClient.dio.patch(
        '/recruiter/drives/$driveId/applicants/$studentId/round',
        data: payload,
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return null;
  }

  // 7. Fetch Recruiter Placement Stats
  Future<Map<String, dynamic>> getRecruiterStats() async {
    try {
      final response = await _apiClient.dio.get('/recruiter/stats');
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return {
      'total_registered_students': 142,
      'total_active_drives': 8,
      'total_offers_made': 12,
    };
  }

  // 8. Fetch Student Published Drives
  Future<List<dynamic>> getPublishedDrives() async {
    final List<dynamic> combined = [];
    final Set<String> seenIds = {};

    try {
      final response = await _apiClient.dio.get('/drives');
      final listData = response.statusCode == 200
          ? (response.data is Map<String, dynamic> ? response.data['items'] : response.data)
          : null;
      if (listData is List) {
        for (var item in listData) {
          final id = (item['drive_id'] ?? item['listing_id'] ?? '').toString();
          final company = (item['company_name'] ?? item['company'] ?? '').toString();
          if (id.isNotEmpty && !seenIds.contains(id) && !ApplicationVisibilityState.instance.isApplied(id, company)) {
            seenIds.add(id);
            combined.add(item);
          }
        }
      }
    } catch (_) {}

    return combined;
  }

  Future<PaginatedResponse<Map<String, dynamic>>> getPublishedDrivesPaginated({int page = 1, int limit = 20}) async {
    try {
      final response = await _apiClient.dio.get('/drives?page=$page&limit=$limit');
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final paginated = PaginatedResponse<Map<String, dynamic>>.fromJson(
          response.data as Map<String, dynamic>,
          (item) => Map<String, dynamic>.from(item as Map),
        );
        final filtered = paginated.items.where((item) {
          final id = (item['drive_id'] ?? item['listing_id'] ?? '').toString();
          final company = (item['company_name'] ?? item['company'] ?? '').toString();
          return !ApplicationVisibilityState.instance.isApplied(id, company);
        }).toList();
        return PaginatedResponse<Map<String, dynamic>>(
          items: filtered,
          page: paginated.page,
          limit: paginated.limit,
          totalCount: paginated.totalCount,
          hasMore: paginated.hasMore,
        );
      }
    } catch (_) {}
    return PaginatedResponse<Map<String, dynamic>>(
      items: [],
      page: page,
      limit: limit,
      totalCount: 0,
      hasMore: false,
    );
  }

  // 8b. Fetch Student Recommended Drives (Matched by verified skills)
  Future<PaginatedResponse<Map<String, dynamic>>> getRecommendedDrivesPaginated({int page = 1, int limit = 20}) async {
    try {
      final response = await _apiClient.dio.get('/drives/recommended?page=$page&limit=$limit');
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final paginated = PaginatedResponse<Map<String, dynamic>>.fromJson(
          response.data as Map<String, dynamic>,
          (item) => Map<String, dynamic>.from(item as Map),
        );
        final filtered = paginated.items.where((item) {
          final id = (item['drive_id'] ?? item['listing_id'] ?? '').toString();
          final company = (item['company_name'] ?? item['company'] ?? '').toString();
          return !ApplicationVisibilityState.instance.isApplied(id, company);
        }).toList();
        return PaginatedResponse<Map<String, dynamic>>(
          items: filtered,
          page: paginated.page,
          limit: paginated.limit,
          totalCount: paginated.totalCount,
          hasMore: paginated.hasMore,
        );
      }
    } catch (_) {}
    return PaginatedResponse<Map<String, dynamic>>(
      items: [],
      page: page,
      limit: limit,
      totalCount: 0,
      hasMore: false,
    );
  }

  // 9. Fetch Drive Detail
  Future<Map<String, dynamic>?> getDriveDetail(String driveId) async {
    try {
      final response = await _apiClient.dio.get('/drives/$driveId');
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return null;
  }

  // 10. Apply to Placement Drive or Company Listing
  Future<Map<String, dynamic>> applyToDrive(String driveId) async {
    try {
      Response response;
      try {
        response = await _apiClient.dio.post('/drives/$driveId/apply');
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          response = await _apiClient.dio.post('/companies/$driveId/apply');
        } else {
          rethrow;
        }
      }

      if (response.statusCode == 201) {
        final body = response.data is Map ? Map<String, dynamic>.from(response.data as Map) : <String, dynamic>{};
        final application = body['application'];
        if (application is Map) {
          ApplicationVisibilityState.instance.recordApplication(Map<String, dynamic>.from(application));
        }
        return {'success': true, 'data': response.data};
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final detail = e.response?.data is Map ? e.response?.data['detail']?.toString() : null;

      if (statusCode == 400 && (detail?.contains('resume') ?? false)) {
        return {
          'success': false,
          'no_resume': true,
          'message': detail ?? 'Please upload a resume first.',
        };
      }
      if (statusCode == 409) {
        return {
          'success': false,
          'conflict': true,
          'message': detail ?? 'You have already applied to this listing.',
        };
      }
      return {
        'success': false,
        'message': detail ?? 'Could not submit application. (Status: $statusCode)',
      };
    } catch (_) {}

    return {'success': false, 'message': 'Unknown error occurred.'};
  }

  // 11. Fetch Student Drive Application Status
  Future<Map<String, dynamic>> getMyDriveStatus(String driveId) async {
    try {
      final response = await _apiClient.dio.get('/drives/$driveId/my-status');
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return {
      'applied': false,
      'current_round': 0,
      'round_history': [],
      'final_outcome': 'not_applied',
    };
  }

  // 12. Fetch Student's Applied Drives (Paginated, single query)
  Future<PaginatedResponse<Map<String, dynamic>>> getMyApplicationsPaginated({int page = 1, int limit = 20}) async {
    try {
      final response = await _apiClient.dio.get('/drives/my-applications?page=$page&limit=$limit');
      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        final paginated = PaginatedResponse<Map<String, dynamic>>.fromJson(
          response.data as Map<String, dynamic>,
          (item) => Map<String, dynamic>.from(item as Map),
        );
        ApplicationVisibilityState.instance.recordMultipleApplications(paginated.items);
        return paginated;
      }
    } catch (_) {}
    return PaginatedResponse<Map<String, dynamic>>(
      items: [],
      page: page,
      limit: limit,
      totalCount: 0,
      hasMore: false,
    );
  }

  // 13. Fetch Email Application Draft
  Future<Map<String, dynamic>?> getEmailDraft(String driveId) async {
    try {
      final response = await _apiClient.dio.get('/drives/$driveId/email-draft');
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return null;
  }

  // 14. Mark Email Client Opened
  Future<bool> markEmailClientOpened(String driveId) async {
    try {
      final response = await _apiClient.dio.post('/drives/$driveId/email-draft/mark-sent');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 15. Fetch Smart AI Match Analysis & Interview Coach
  Future<Map<String, dynamic>?> getDriveAIMatch(String driveId, {bool bypassCache = false}) async {
    try {
      final response = await _apiClient.dio.get(
        '/drives/$driveId/ai-match${bypassCache ? "?bypass_cache=true" : ""}',
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return null;
  }

  // 16. Setup / Issue Placement Offer (Recruiter)
  Future<bool> setupOffer({
    required String driveId,
    required String studentId,
    required Map<String, dynamic> offerData,
  }) async {
    try {
      final response = await _apiClient.dio.post(
        '/recruiter/drives/$driveId/applications/$studentId/offer',
        data: offerData,
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[SETUP OFFER ERROR] $e');
      return false;
    }
  }

  // 17. Accept Placement Offer (Student)
  Future<bool> acceptOffer(String driveId) async {
    try {
      final response = await _apiClient.dio.post('/drives/$driveId/accept-offer');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ACCEPT OFFER ERROR] $e');
      return false;
    }
  }

  // 18. Decline Placement Offer (Student)
  Future<bool> declineOffer(String driveId, {String? reason}) async {
    try {
      final response = await _apiClient.dio.post(
        '/drives/$driveId/decline-offer',
        data: reason != null ? {'reason': reason} : null,
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[DECLINE OFFER ERROR] $e');
      return false;
    }
  }

  // 19. Fetch Campus Broadcast Announcements (Student)
  Future<List<Map<String, dynamic>>> getBroadcastAnnouncements() async {
    try {
      final response = await _apiClient.dio.get('/announcements');
      if (response.statusCode == 200 && response.data is Map) {
        final list = (response.data['announcements'] as List?) ?? [];
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[GET ANNOUNCEMENTS ERROR] $e');
    }
    return [];
  }
}
