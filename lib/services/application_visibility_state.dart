import 'package:flutter/foundation.dart';

/// Broadcasts successful applications to screens that may already be mounted.
/// The server remains the source of truth; this only removes stale UI/cache
/// windows after the apply response has been received.
class ApplicationVisibilityState extends ChangeNotifier {
  ApplicationVisibilityState._();
  static final instance = ApplicationVisibilityState._();

  final Map<String, Map<String, dynamic>> _applications = {};

  bool isApplied(String driveId) => _applications.containsKey(driveId);

  void recordApplication(Map<String, dynamic> application) {
    final driveId = application['drive_id']?.toString();
    if (driveId == null || driveId.isEmpty) return;
    _applications[driveId] = Map<String, dynamic>.from(application);
    notifyListeners();
  }
}
