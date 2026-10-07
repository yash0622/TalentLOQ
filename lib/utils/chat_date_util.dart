import 'package:intl/intl.dart';

/// Formats raw chat timestamp (e.g. ISO 8601 strings like "2026-10-06T04:13:55.975000")
/// into clean, user-friendly timestamps like "4:13 AM", "Yesterday, 4:13 AM", etc.
String formatChatTimestamp(String raw) {
  if (raw.isEmpty) return '';
  final trimmed = raw.trim();

  // If already formatted like 'Always Active', 'Just Now', or already has AM/PM
  if (trimmed.toLowerCase().contains('always') ||
      trimmed.toLowerCase().contains('just now') ||
      trimmed.toLowerCase().contains('am') ||
      trimmed.toLowerCase().contains('pm')) {
    return trimmed;
  }

  try {
    DateTime? parsed = DateTime.tryParse(trimmed);
    if (parsed == null) return trimmed;

    final local = parsed.toLocal();
    final now = DateTime.now();

    final isToday = local.year == now.year && local.month == now.month && local.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = local.year == yesterday.year && local.month == yesterday.month && local.day == yesterday.day;

    final timeStr = DateFormat('h:mm a').format(local);

    if (isToday) {
      return timeStr;
    } else if (isYesterday) {
      return 'Yesterday, $timeStr';
    } else if (local.year == now.year) {
      return DateFormat('MMM d, h:mm a').format(local);
    } else {
      return DateFormat('MMM d, y, h:mm a').format(local);
    }
  } catch (_) {
    return trimmed;
  }
}

/// Formats conversation list tile timestamp (short format for list sidebar/feed)
String formatConversationTime(String raw) {
  if (raw.isEmpty) return '';
  final trimmed = raw.trim();

  if (trimmed.toLowerCase().contains('always') ||
      trimmed.toLowerCase().contains('just now')) {
    return trimmed;
  }

  try {
    DateTime? parsed = DateTime.tryParse(trimmed);
    if (parsed == null) return trimmed;

    final local = parsed.toLocal();
    final now = DateTime.now();

    final isToday = local.year == now.year && local.month == now.month && local.day == now.day;
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = local.year == yesterday.year && local.month == yesterday.month && local.day == yesterday.day;

    if (isToday) {
      return DateFormat('h:mm a').format(local);
    } else if (isYesterday) {
      return 'Yesterday';
    } else if (local.year == now.year) {
      return DateFormat('MMM d').format(local);
    } else {
      return DateFormat('dd/MM/yy').format(local);
    }
  } catch (_) {
    return trimmed;
  }
}
