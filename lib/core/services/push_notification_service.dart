import 'package:flutter/services.dart';

/// Native Android push / heads-up notification bridge for Messages & Voice Calls
/// (works on Firebase Spark free tier with Android 13+ POST_NOTIFICATIONS support).
class PushNotificationService {
  static const MethodChannel _channel = MethodChannel('melow/notifications');

  /// Tracks which friend chat screen is currently open on screen so we don't
  /// show a redundant notification banner for the active conversation in foreground.
  static String? _activeChatFriendUid;
  static String? get activeChatFriendUid => _activeChatFriendUid;
  static set activeChatFriendUid(String? uid) {
    _activeChatFriendUid = uid;
    try {
      _channel.invokeMethod('setActiveChatFriendUid', {'friendUid': uid});
    } catch (_) {}
  }

  /// Registers a callback invoked when the user taps "Answer" on an incoming call
  /// notification from the lock screen or while using another app.
  static void setOnAnswerCallFromNotification(
    void Function(String callId)? handler,
  ) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAnswerCallFromNotification') {
        final callId = call.arguments as String?;
        if (callId != null && callId.isNotEmpty && handler != null) {
          handler(callId);
        }
      }
    });
  }

  static Future<String?> consumePendingAutoAnswerCallId() async {
    try {
      return await _channel
          .invokeMethod<String>('consumePendingAutoAnswerCallId');
    } catch (_) {
      return null;
    }
  }

  static int messageNotificationIdFor(String chatId) =>
      100000 + (chatId.hashCode & 0x7FFF);

  static Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestNotificationPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> showMessageNotification({
    required String chatId,
    required String senderName,
    required String messagePreview,
    required int unreadCount,
  }) async {
    try {
      final title = unreadCount > 1
          ? '$senderName ($unreadCount new messages)'
          : senderName;
      await _channel.invokeMethod('showMessageNotification', {
        'id': messageNotificationIdFor(chatId),
        'title': title,
        'body': messagePreview.isNotEmpty ? messagePreview : 'Sent you a message',
        'count': unreadCount,
      });
    } catch (_) {}
  }

  static Future<void> cancelMessageNotification(String chatId) async {
    try {
      await _channel.invokeMethod('cancelMessageNotification', {
        'id': messageNotificationIdFor(chatId),
      });
    } catch (_) {}
  }

  static Future<void> showCallNotification({
    required String callId,
    required String callerName,
    bool isGroupCall = false,
    String? groupName,
  }) async {
    try {
      await _channel.invokeMethod('showCallNotification', {
        'callId': callId,
        'callerName': callerName,
        'isGroupCall': isGroupCall,
        'groupName': groupName,
      });
    } catch (_) {}
  }

  static Future<void> cancelCallNotification(String callId) async {
    try {
      await _channel.invokeMethod('cancelCallNotification', {
        'callId': callId,
      });
    } catch (_) {}
  }

  /// Starts the native Android real-time background service (`MelowRealtimeAlertService`)
  /// so incoming calls, messages, friend requests, and challenges ring and show
  /// heads-up notifications even when the phone is locked or in another app.
  static Future<void> startBackgroundKeepAlive({String? uid}) async {
    try {
      await _channel.invokeMethod('startBackgroundKeepAlive', {
        if (uid != null && uid.isNotEmpty) 'uid': uid,
      });
    } catch (_) {}
  }

  static Future<void> stopBackgroundKeepAlive() async {
    try {
      await _channel.invokeMethod('stopBackgroundKeepAlive');
    } catch (_) {}
  }
}
