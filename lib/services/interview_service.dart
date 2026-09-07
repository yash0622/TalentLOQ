import 'package:flutter/foundation.dart';
import '../network/api_client.dart';
import '../models/models.dart';
import '../mock_data/mock_data.dart';

class InterviewService {
  final ApiClient _apiClient = ApiClient.instance;

  /// Schedule interview with candidate
  Future<bool> scheduleInterview({
    required String studentId,
    required String candidateName,
    required String date,
    required String timeSlot,
    required String interviewType,
    String? driveId,
  }) async {
    try {
      final payload = <String, dynamic>{
        'student_id': studentId,
        'candidate_name': candidateName,
        'date': date,
        'time_slot': timeSlot,
        'interview_type': interviewType,
      };
      if (driveId != null) payload['drive_id'] = driveId;

      final response = await _apiClient.dio.post('/interviews/schedule', data: payload);

      if (response.statusCode == 201 || response.statusCode == 200) {
        MockData.interviewSlots.add(
          InterviewSlot(
            id: 'intv-${DateTime.now().millisecondsSinceEpoch}',
            date: date,
            time: timeSlot,
            candidateName: candidateName,
            position: interviewType,
            type: interviewType,
            isBooked: true,
            status: 'scheduled',
            feedback: '',
          ),
        );
        return true;
      }
    } catch (e) {
      debugPrint('[INTERVIEW SCHEDULE ERROR] $e');
    }
    return false;
  }

  /// Fetch user's scheduled interviews
  Future<List<Map<String, dynamic>>> getMyInterviews() async {
    try {
      final response = await _apiClient.dio.get('/interviews/my-interviews');
      if (response.statusCode == 200 && response.data is Map) {
        final list = (response.data['interviews'] as List?) ?? [];
        return list.map((i) => Map<String, dynamic>.from(i as Map)).toList();
      }
    } catch (_) {}
    return [];
  }
}