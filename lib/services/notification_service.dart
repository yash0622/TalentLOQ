import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'auth_service.dart';
import 'token_storage_service.dart';
import '../screens/profile/profile_applications_screen.dart';
import '../screens/profile/document_verification_screen.dart';
import '../screens/chat/messages_list_screen.dart';
import '../screens/jobs/jobs_section_screen.dart';

/// Top-level background message handler required by Firebase Messaging
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    debugPrint('[FCM Background] Message ID: ${message.messageId}');
    debugPrint('[FCM Background] Data: ${message.data}');
  } catch (e) {
    debugPrint('[FCM Background] Error in background handler: $e');
  }
}

class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  /// Global navigator key for deep linking navigation across the app
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final AuthService _authService = AuthService();
  final TokenStorageService _tokenStorage = TokenStorageService();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important TalentLOQ updates, interview alerts, and messages.',
    importance: Importance.high,
    playSound: true,
  );

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  bool _initialized = false;

  /// Initializes Firebase Core, Firebase Messaging, and Local Notifications without blocking startup.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // 1. Initialize Firebase App
      await Firebase.initializeApp();
      debugPrint('[FCM] Firebase initialized successfully');

      // 2. Set Background Message Handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 3. Request permissions (Android 13+ POST_NOTIFICATIONS and iOS)
      await requestPermissions();

      // 4. Initialize Flutter Local Notifications for heads-up foreground alerts
      const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
      const iosInit = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('[FCM Local] Notification tapped: ${response.payload}');
          _handleNotificationPayload(response.payload);
        },
      );

      // Create Android Notification Channel
      final androidPlatformPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlatformPlugin != null) {
        await androidPlatformPlugin.createNotificationChannel(_channel);
      }

      // 5. Configure Foreground presentation options
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 6. Retrieve and register FCM Device Token
      await _fetchAndSyncToken();

      // Listen for token updates
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        debugPrint('[FCM] Token refreshed: $newToken');
        _fcmToken = newToken;
        _authService.registerDeviceToken(newToken);
      });

      // 7. Foreground Message Listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[FCM Foreground] Received: ${message.notification?.title} - ${message.notification?.body}');
        _showForegroundNotification(message);
      });

      // 8. Notification opened from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[FCM OpenedApp] User tapped notification: ${message.data}');
        handleDeepLink(message.data);
      });

      // 9. Initial message if app was launched from terminated state
      final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('[FCM InitialMessage] App opened from terminated notification: ${initialMessage.data}');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          handleDeepLink(initialMessage.data);
        });
      }

      _initialized = true;
    } catch (e, stack) {
      debugPrint('[FCM] Failed to initialize Firebase Messaging: $e');
      debugPrint(stack.toString());
    }
  }

  /// Request permissions for iOS and Android 13+ (POST_NOTIFICATIONS)
  Future<NotificationSettings> requestPermissions() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    debugPrint('[FCM] Permission authorization status: ${settings.authorizationStatus}');
    return settings;
  }

  /// Fetches FCM token and syncs it with the backend database.
  Future<String?> _fetchAndSyncToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        _fcmToken = token;
        debugPrint('[FCM] Device Token: $token');
        await _authService.registerDeviceToken(token);
      }
      return token;
    } catch (e) {
      debugPrint('[FCM] Error fetching token: $e');
      return null;
    }
  }

  /// Manually syncs token (e.g. right after a user logs in).
  Future<void> syncTokenWithBackend() async {
    if (_fcmToken != null) {
      await _authService.registerDeviceToken(_fcmToken!);
    } else {
      await _fetchAndSyncToken();
    }
  }

  /// Revokes device token on logout.
  Future<void> unregisterOnLogout() async {
    try {
      await _authService.logout();
      await FirebaseMessaging.instance.deleteToken();
      _fcmToken = null;
    } catch (e) {
      debugPrint('[FCM] Error during logout token revocation: $e');
    }
  }

  /// Displays an in-app heads-up notification banner when a push arrives in the foreground.
  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] ?? 'TalentLOQ Notification';
    final body = notification?.body ?? message.data['body'] ?? '';

    _localNotifications.show(
      id: (notification?.hashCode ?? DateTime.now().millisecondsSinceEpoch) & 0x7FFFFFFF,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          icon: '@mipmap/launcher_icon',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void _handleNotificationPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload);
      if (data is Map<String, dynamic>) {
        handleDeepLink(data);
      }
    } catch (_) {}
  }

  /// Deep linking dispatcher based on payload 'type' and 'entity_id'
  void handleDeepLink(Map<String, dynamic> data) async {
    final navState = navigatorKey.currentState;
    if (navState == null) {
      debugPrint('[FCM DeepLink] NavigatorState not available yet.');
      return;
    }

    final type = (data['type'] ?? '').toString().toLowerCase();
    debugPrint('[FCM DeepLink] Dispatching deep link for type: $type, data: $data');

    final isLoggedIn = await _tokenStorage.getIsLoggedIn();
    if (!isLoggedIn) {
      debugPrint('[FCM DeepLink] User not logged in. Deep linking requires login first.');
      return;
    }

    switch (type) {
      case 'drive_published':
      case 'company_published':
      case 'deadline_reminder':
        navState.push(
          MaterialPageRoute(
            builder: (_) => const Scaffold(
              body: JobsSectionScreen(),
            ),
          ),
        );
        break;

      case 'round_outcome':
      case 'applicant_shortlisted':
      case 'applicant_rejected':
      case 'offer':
      case 'offer_recorded':
        navState.push(
          MaterialPageRoute(
            builder: (_) => ProfileApplicationsScreen(
              onSelectJob: (_) {},
            ),
          ),
        );
        break;

      case 'chat_message':
      case 'new_message':
        navState.push(
          MaterialPageRoute(
            builder: (_) => MessagesListScreen(
              onSelectConversation: (_) {},
            ),
          ),
        );
        break;

      case 'document_status':
      case 'document_verified':
      case 'document_rejected':
        navState.push(
          MaterialPageRoute(
            builder: (_) => const DocumentVerificationScreen(),
          ),
        );
        break;

      default:
        debugPrint('[FCM DeepLink] Unrecognized notification type: $type');
        break;
    }
  }
}
