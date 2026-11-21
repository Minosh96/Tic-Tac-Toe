import 'package:flutter/services.dart';

/// Native Android push / heads-up notification bridge for Messages & Voice Calls
/// (works on Firebase Spark free tier with Android 13+ POST_NOTIFICATIONS support).
class PushNotificationService {
  static const MethodChannel _channel = MethodChannel('melow/notifications');

  /// Tracks which friend chat screen is currently open on screen so we don't
  /// show a redundant notification banner for the active conversation in foreground.
  static String? activeChatFriendUid;

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
  }) async {
    try {
      await _channel.invokeMethod('showCallNotification', {
        'callId': callId,
        'callerName': callerName,
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

  /// Starts Android foreground keep-alive service so live messages & voice calls
  /// still wake the phone and ring even while the phone is locked.
  static Future<void> startBackgroundKeepAlive() async {
    try {
      await _channel.invokeMethod('startBackgroundKeepAlive');
    } catch (_) {}
  }

  static Future<void> stopBackgroundKeepAlive() async {
    try {
      await _channel.invokeMethod('stopBackgroundKeepAlive');
    } catch (_) {}
  }
}
