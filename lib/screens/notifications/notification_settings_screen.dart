import 'package:flutter/material.dart';
import '../../services/notification_inbox_service.dart';
import '../../theme/app_colors.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final NotificationInboxService _inboxService = NotificationInboxService.instance;

  bool _isLoading = true;
  bool _driveAlerts = true;
  bool _roundResults = true;
  bool _offers = true;
  bool _chatMessages = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await _inboxService.getPreferences();
    if (mounted) {
      setState(() {
        _driveAlerts = prefs['drive_alerts'] ?? true;
        _roundResults = prefs['round_results'] ?? true;
        _offers = prefs['offers'] ?? true;
        _chatMessages = prefs['chat_messages'] ?? true;
        _isLoading = false;
      });
    }
  }

  Future<void> _savePreferences() async {
    await _inboxService.updatePreferences({
      'drive_alerts': _driveAlerts,
      'round_results': _roundResults,
      'offers': _offers,
      'chat_messages': _chatMessages,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Preferences', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Control the notifications you receive on your device. In-app inbox will continue to log all relevant updates.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Placement Drive Alerts', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('New drive announcements and 24h/2h deadline reminders'),
                        secondary: const Icon(Icons.business_center_rounded, color: AppColors.lightPrimary),
                        value: _driveAlerts,
                        onChanged: (val) {
                          setState(() => _driveAlerts = val);
                          _savePreferences();
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Round Results & Progress', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Outcome alerts when you advance or get shortlisted'),
                        secondary: const Icon(Icons.how_to_reg_rounded, color: Colors.blue),
                        value: _roundResults,
                        onChanged: (val) {
                          setState(() => _roundResults = val);
                          _savePreferences();
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Placement Offers', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Official job and internship offer announcements'),
                        secondary: const Icon(Icons.verified_rounded, color: Colors.green),
                        value: _offers,
                        onChanged: (val) {
                          setState(() => _offers = val);
                          _savePreferences();
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Chat & Direct Messages', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Alerts for new messages from recruiters and coordinators'),
                        secondary: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.purple),
                        value: _chatMessages,
                        onChanged: (val) {
                          setState(() => _chatMessages = val);
                          _savePreferences();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
