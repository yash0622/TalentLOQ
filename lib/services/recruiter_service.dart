import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../network/api_client.dart';
import '../controllers/paging_controller.dart';
import 'token_storage_service.dart';
import '../utils/jwt_decoder_util.dart';

class RecruiterService {
  final ApiClient _apiClient = ApiClient.instance;
  final TokenStorageService _tokenStorage = TokenStorageService();

  // 1. Create Job / Drive Listing (Multipart FormData)
  Future<bool> createCompanyListing(Map<String, dynamic> data, String? pdfFilePath) async {
    try {
      final mapData = Map<String, dynamic>.from(data);

      if (pdfFilePath != null && pdfFilePath.isNotEmpty) {
        mapData['pdf'] = await MultipartFile.fromFile(
          pdfFilePath,
          filename: pdfFilePath.split('/').last.split('\\').last,
        );
      }

      final formData = FormData.fromMap(mapData);
      
      // Try /recruiter/drives first, fallback to /recruiter/companies
      try {
        final res = await _apiClient.dio.post('/recruiter/drives', data: formData);
        if (res.statusCode == 201) return true;
      } catch (_) {}

      final response = await _apiClient.dio.post('/recruiter/companies', data: formData);
      return response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // 2. Edit Job / Drive Listing
  Future<bool> editCompanyListing(String listingId, Map<String, dynamic> updateData) async {
    try {
      try {
        final res = await _apiClient.dio.patch('/recruiter/drives/$listingId', data: updateData);
        if (res.statusCode == 200) return true;
      } catch (_) {}

      final response = await _apiClient.dio.patch('/recruiter/companies/$listingId', data: updateData);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 3. Publish Listing
  Future<bool> publishCompanyListing(String listingId) async {
    try {
      try {
        final res = await _apiClient.dio.post('/recruiter/drives/$listingId/publish');
        if (res.statusCode == 200) return true;
      } catch (_) {}

      final response = await _apiClient.dio.post('/recruiter/companies/$listingId/publish');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // 4. Fetch Recruiter Listings
  Future<List<dynamic>> getRecruiterListings() async {
    final List<dynamic> combined = [];
    final Set<String> seenIds = {};

    List<dynamic> extractList(dynamic data) {
      if (data is Map && data['items'] is List) {
        return data['items'] as List<dynamic>;
      } else if (data is List) {
        return data;
      }
      return [];
    }

    final token = await _tokenStorage.getAccessToken();
    final role = (token != null ? JwtDecoderUtil.getRoleFromToken(token) : null) ??
        await _tokenStorage.getUserRole();
    if (role != null && role != 'recruiter' && role != 'admin') {
      try {
        final res = await _apiClient.dio.get('/drives');
        if (res.statusCode == 200) {
          final list = extractList(res.data);
          for (var item in list) {
            final id = (item['drive_id'] ?? item['listing_id'] ?? '').toString();
            if (id.isNotEmpty && !seenIds.contains(id)) {
              seenIds.add(id);
              combined.add(item);
            }
          }
        }
      } catch (_) {}
      return combined;
    }

    try {
      final res = await _apiClient.dio.get('/recruiter/drives');
      if (res.statusCode == 200) {
        final list = extractList(res.data);
        for (var item in list) {
          final id = (item['drive_id'] ?? item['listing_id'] ?? '').toString();
          if (id.isNotEmpty && !seenIds.contains(id)) {
            seenIds.add(id);
            combined.add(item);
          }
        }
      }
    } catch (_) {}

    try {
      final res2 = await _apiClient.dio.get('/recruiter/companies');
      if (res2.statusCode == 200) {
        final list = extractList(res2.data);
        for (var item in list) {
          final id = (item['listing_id'] ?? item['drive_id'] ?? '').toString();
          if (id.isNotEmpty && !seenIds.contains(id)) {
            seenIds.add(id);
            combined.add(item);
          }
        }
      }
    } catch (_) {}

    return combined;
  }

  // 4b. Fetch Drive Detail
  Future<Map<String, dynamic>?> getDriveDetail(String driveId) async {
    try {
      final res = await _apiClient.dio.get('/recruiter/drives/$driveId');
      if (res.statusCode == 200 && res.data is Map) {
        return Map<String, dynamic>.from(res.data as Map);
      }
    } catch (_) {}
    return null;
  }

  // 5. Fetch Applicants for a Listing
  Future<List<dynamic>> getListingApplicants(String listingId) async {
    try {
      final res = await _apiClient.dio.get('/recruiter/drives/$listingId/applicants');
      if (res.statusCode == 200 && res.data != null) {
        if (res.data is Map<String, dynamic> && res.data['items'] != null) {
          final list = (res.data['items'] as List);
          if (list.isNotEmpty) return list;
        } else if (res.data is List) {
          final list = res.data as List;
          if (list.isNotEmpty) return list;
        }
      }
    } catch (_) {}

    try {
      final res2 = await _apiClient.dio.get('/recruiter/companies/$listingId/applicants');
      if (res2.statusCode == 200 && res2.data != null) {
        if (res2.data is Map<String, dynamic> && res2.data['items'] != null) {
          final list = (res2.data['items'] as List);
          if (list.isNotEmpty) return list;
        } else if (res2.data is List) {
          final list = res2.data as List;
          if (list.isNotEmpty) return list;
        }
      }
    } catch (_) {}

    return [];
  }

  Future<PaginatedResponse<Map<String, dynamic>>> getListingApplicantsPaginated(
    String listingId, {
    int page = 1,
    int limit = 20,
  }) async {
    Map<String, dynamic>? safeMap(dynamic item) {
      if (item is Map) {
        return Map<String, dynamic>.from(item);
      }
      return null;
    }

    // 1. Try /recruiter/drives/$listingId/applicants
    try {
      final response = await _apiClient.dio.get('/recruiter/drives/$listingId/applicants?page=$page&limit=$limit');
      if (response.statusCode == 200 && response.data != null) {
        if (response.data is Map) {
          final map = Map<String, dynamic>.from(response.data as Map);
          final rawItems = map['items'] as List<dynamic>? ?? [];
          final itemsList = rawItems.map(safeMap).whereType<Map<String, dynamic>>().toList();
          final total = map['total_count'] is int ? (map['total_count'] as int) : itemsList.length;

          return PaginatedResponse<Map<String, dynamic>>(
            items: itemsList,
            page: map['page'] is int ? (map['page'] as int) : page,
            limit: map['limit'] is int ? (map['limit'] as int) : limit,
            totalCount: total,
            hasMore: map['has_more'] is bool ? (map['has_more'] as bool) : false,
          );
        } else if (response.data is List) {
          final rawList = (response.data as List).map(safeMap).whereType<Map<String, dynamic>>().toList();
          return PaginatedResponse<Map<String, dynamic>>(
            items: rawList,
            page: 1,
            limit: rawList.length,
            totalCount: rawList.length,
            hasMore: false,
          );
        }
      }
    } catch (_) {}

    // 2. Try /recruiter/companies/$listingId/applicants
    try {
      final response = await _apiClient.dio.get('/recruiter/companies/$listingId/applicants');
      if (response.statusCode == 200 && response.data != null) {
        if (response.data is List) {
          final rawList = (response.data as List).map(safeMap).whereType<Map<String, dynamic>>().toList();
          return PaginatedResponse<Map<String, dynamic>>(
            items: rawList,
            page: 1,
            limit: rawList.length,
            totalCount: rawList.length,
            hasMore: false,
          );
        } else if (response.data is Map) {
          final map = Map<String, dynamic>.from(response.data as Map);
          final rawItems = map['items'] as List<dynamic>? ?? [];
          final itemsList = rawItems.map(safeMap).whereType<Map<String, dynamic>>().toList();
          return PaginatedResponse<Map<String, dynamic>>(
            items: itemsList,
            page: map['page'] is int ? (map['page'] as int) : page,
            limit: map['limit'] is int ? (map['limit'] as int) : limit,
            totalCount: (map['total_count'] is int) ? map['total_count'] as int : itemsList.length,
            hasMore: map['has_more'] is bool ? map['has_more'] as bool : false,
          );
        }
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

  // 6. Fetch Candidates matching a Drive's skills
  Future<PaginatedResponse<Map<String, dynamic>>> getMatchingStudentsPaginated(
    String driveId, {
    String matchType = 'any',
    double? minCgpa,
    int page = 1,
    int limit = 20,
  }) async {
    Map<String, dynamic>? safeMap(dynamic item) {
      if (item is Map) {
        return Map<String, dynamic>.from(item);
      }
      return null;
    }

    try {
      var url = '/recruiter/drives/$driveId/matching-students?match_type=$matchType&page=$page&limit=$limit';
      if (minCgpa != null && minCgpa > 0) {
        url += '&min_cgpa=$minCgpa';
      }
      final response = await _apiClient.dio.get(url);
      if (response.statusCode == 200 && response.data != null && response.data is Map) {
        final map = Map<String, dynamic>.from(response.data as Map);
        final rawItems = map['items'] as List<dynamic>? ?? [];
        final itemsList = rawItems.map(safeMap).whereType<Map<String, dynamic>>().toList();
        final total = map['total_count'] is int ? (map['total_count'] as int) : itemsList.length;

        return PaginatedResponse<Map<String, dynamic>>(
          items: itemsList,
          page: map['page'] is int ? (map['page'] as int) : page,
          limit: map['limit'] is int ? (map['limit'] as int) : limit,
          totalCount: total,
          hasMore: map['has_more'] is bool ? (map['has_more'] as bool) : false,
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
  Future<Map<String, dynamic>?> updateApplicantRound(String listingId, String studentId, String result) async {
    try {
      final response = await _apiClient.dio.patch(
        '/recruiter/drives/$listingId/applicants/$studentId/round',
        data: {'result': result},
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return null;
  }

  // 7. Fetch Recruiter Stats
  Future<Map<String, dynamic>> getRecruiterStats() async {
    try {
      final response = await _apiClient.dio.get('/recruiter/stats');
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return {
      'total_registered_students': 0,
      'total_active_listings': 0,
      'total_active_drives': 0,
      'total_offers_made': 0,
    };
  }

  // 8. Post Announcement
  Future<bool> postAnnouncement(String title, String message, {String target = "ALL"}) async {
    try {
      final response = await _apiClient.dio.post(
        '/recruiter/announcements',
        data: {'title': title, 'content': message, 'message': message, 'target_audience': target},
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[POST ANNOUNCEMENT ERROR] $e');
      return false;
    }
  }

  // 8b. Fetch Recruiter Announcements
  Future<List<Map<String, dynamic>>> getAnnouncements() async {
    try {
      final response = await _apiClient.dio.get('/recruiter/announcements');
      if (response.statusCode == 200 && response.data is Map) {
        final list = (response.data['announcements'] as List?) ?? [];
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[GET ANNOUNCEMENTS ERROR] $e');
    }
    return [];
  }

  // 9. Log Interview Outcome
  Future<bool> logInterviewOutcome(String interviewId, String outcome, [String? notes]) async {
    try {
      String normalizedOutcome = outcome.toLowerCase().trim();
      if (normalizedOutcome == 'pass' || normalizedOutcome == 'selected') {
        normalizedOutcome = 'passed';
      } else if (normalizedOutcome == 'fail' || normalizedOutcome == 'rejected') {
        normalizedOutcome = 'failed';
      } else if (!['passed', 'failed', 'next_round'].contains(normalizedOutcome)) {
        normalizedOutcome = 'next_round';
      }

      final response = await _apiClient.dio.post(
        '/recruiter/interviews/$interviewId/outcome',
        data: {
          'status': normalizedOutcome,
          'outcome': normalizedOutcome,
          'feedback': notes ?? '',
          'notes': notes ?? '',
        },
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // 10. Fetch Registered Students List
  Future<List<dynamic>> getRegisteredStudents() async {
    try {
      final response = await _apiClient.dio.get('/recruiter/students');
      if (response.statusCode == 200) {
        if (response.data is Map && response.data['items'] is List) {
          return response.data['items'] as List<dynamic>;
        } else if (response.data is List) {
          return response.data as List<dynamic>;
        }
      }
    } catch (_) {}
    return [];
  }

  // 11. Fetch Drive Talent Comparison & Rankings
  Future<Map<String, dynamic>?> getTalentComparison(String driveId) async {
    try {
      final response = await _apiClient.dio.get('/recruiter/drives/$driveId/talent-comparison');
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return null;
  }

  // 12. Fetch Applicant AI Screening Insight & Interview Cheat Sheet
  Future<Map<String, dynamic>?> getApplicantAIInsight(String driveId, String studentId, {bool bypassCache = false}) async {
    try {
      final response = await _apiClient.dio.get(
        '/recruiter/drives/$driveId/applicants/$studentId/ai-insight${bypassCache ? "?bypass_cache=true" : ""}',
      );
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return null;
  }

  // 13. Fetch Student Academic Record & Documents for Recruiter
  Future<Map<String, dynamic>?> getStudentAcademicRecord(String studentId) async {
    try {
      final response = await _apiClient.dio.get('/recruiter/students/$studentId/academic-record');
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } catch (_) {}
    return null;
  }

  // 14. Fetch Validation Applicants across all drives
  Future<List<Map<String, dynamic>>> getValidationApplicants({String? validationStatus}) async {
    try {
      final query = (validationStatus != null && validationStatus.isNotEmpty && validationStatus.toLowerCase() != 'all')
          ? '?validation_status=${validationStatus.toLowerCase()}'
          : '';
      final response = await _apiClient.dio.get('/recruiter/validation/applicants$query');
      if (response.statusCode == 200 && response.data is Map) {
        final list = (response.data['applicants'] as List?) ?? [];
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[GET VALIDATION APPLICANTS ERROR] $e');
    }
    return [];
  }

  // 15. Update Candidate Validation Status (valid / not_valid)
  Future<bool> updateApplicationValidation(String appId, String validationStatus) async {
    try {
      final response = await _apiClient.dio.post(
        '/recruiter/applications/$appId/validate',
        data: {'validation_status': validationStatus},
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[UPDATE VALIDATION ERROR] $e');
      return false;
    }
  }
}
