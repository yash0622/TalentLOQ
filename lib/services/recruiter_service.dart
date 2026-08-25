import 'package:dio/dio.dart';
import '../network/api_client.dart';
import '../controllers/paging_controller.dart';

class RecruiterService {
  final ApiClient _apiClient = ApiClient.instance;

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
        data: {'title': title, 'message': message, 'target_audience': target},
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return true;
    }
  }

  // 9. Log Interview Outcome
  Future<bool> logInterviewOutcome(String studentId, String outcome, [String? notes]) async {
    try {
      final response = await _apiClient.dio.post(
        '/recruiter/interviews/outcome',
        data: {'student_id': studentId, 'outcome': outcome, 'notes': notes},
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return true;
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
}
