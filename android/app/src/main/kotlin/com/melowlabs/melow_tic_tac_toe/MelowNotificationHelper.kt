package com.melowlabs.melow_tic_tac_toe

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore

/**
 * Shared WhatsApp-style Notification & Ringing helper used by both MainActivity
 * and MelowRealtimeAlertService so calls and messages ring and pop up even when
 * the phone screen is locked or the user is in another app.
 */
object MelowNotificationHelper {
    const val NOTIF_CH_MESSAGES = "melow_messages_v2"
    const val NOTIF_CH_CALLS = "melow_calls_v2"
    const val NOTIF_CH_SERVICE = "melow_realtime_standby"
    const val ACTION_DECLINE_CALL = "com.melowlabs.melow_tic_tac_toe.ACTION_DECLINE_CALL"
    const val EXTRA_CALL_ID = "extra_call_id"
    const val EXTRA_AUTO_ANSWER_CALL_ID = "extra_auto_answer_call_id"

    @Volatile
    private var activeRingtone: Ringtone? = null

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val msgChannel = NotificationChannel(
            NOTIF_CH_MESSAGES,
            "Chat Messages & Challenges",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Instant heads-up alerts for messages, group chats, friend requests & challenges"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 250, 120, 250)
            setShowBadge(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(msgChannel)

        val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val callAudioAttr = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val callChannel = NotificationChannel(
            NOTIF_CH_CALLS,
            "Incoming Voice Calls",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Incoming 1-on-1 and Group voice calls"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 600, 350, 600, 350, 600)
            setSound(ringtoneUri, callAudioAttr)
            setShowBadge(true)
            setBypassDnd(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(callChannel)

        val serviceChannel = NotificationChannel(
            NOTIF_CH_SERVICE,
            "Real-Time Call & Message Standby",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps Melow ready to receive incoming voice calls and messages while locked"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }
        nm.createNotificationChannel(serviceChannel)
    }

    fun canPostNotifications(context: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
    }

    fun wakeScreen(context: Context, durationMs: Long) {
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isInteractive) {
                @Suppress("DEPRECATION")
                val wl = pm.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                    "melow:alert_wake"
                )
                wl.acquire(durationMs)
            }
        } catch (_: Exception) {
        }
    }

    fun createOpenAppPendingIntent(
        context: Context,
        reqCode: Int,
        autoAnswerCallId: String? = null
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (!autoAnswerCallId.isNullOrEmpty()) {
                putExtra(EXTRA_AUTO_ANSWER_CALL_ID, autoAnswerCallId)
            }
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getActivity(context, reqCode, intent, flags)
    }

    private fun createDeclineCallPendingIntent(context: Context, callId: String): PendingIntent {
        val intent = Intent(context, MelowNotificationActionReceiver::class.java).apply {
            action = ACTION_DECLINE_CALL
            putExtra(EXTRA_CALL_ID, callId)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(context, callNotificationId(callId) + 1, intent, flags)
    }

    fun messageNotificationId(chatId: String): Int =
        100000 + (chatId.hashCode() and 0x7FFF)

    fun callNotificationId(callId: String): Int =
        200000 + (callId.hashCode() and 0x7FFF)

    fun showMessageNotification(
        context: Context,
        notifId: Int,
        title: String,
        body: String,
        count: Int
    ) {
        if (!canPostNotifications(context)) return
        ensureChannels(context)
        wakeScreen(context, 4000L)
        val openPending = createOpenAppPendingIntent(context, notifId)
        val builder = NotificationCompat.Builder(context, NOTIF_CH_MESSAGES)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setNumber(count)
            .setContentIntent(openPending)
            .setFullScreenIntent(openPending, false)
        try {
            NotificationManagerCompat.from(context).notify(notifId, builder.build())
        } catch (_: SecurityException) {
        }
    }

    fun showCallNotification(
        context: Context,
        callId: String,
        callerName: String,
        isGroupCall: Boolean = false,
        groupName: String? = null
    ) {
        if (!canPostNotifications(context)) return
        ensureChannels(context)
        wakeScreen(context, 15000L)
        startRingingTone(context)

        val id = callNotificationId(callId)
        val openAndAnswerPending = createOpenAppPendingIntent(
            context,
            id,
            autoAnswerCallId = callId
        )
        val declinePending = createDeclineCallPendingIntent(context, callId)

        val title = if (isGroupCall) {
            "📞 Incoming Group Call (${groupName ?: "Group"})"
        } else {
            "📞 Incoming Voice Call"
        }
        val body = if (isGroupCall) {
            "$callerName started a Group Voice Call • Tap Answer to join!"
        } else {
            "$callerName is calling you on Melow Tic Tac Toe"
        }

        val builder = NotificationCompat.Builder(context, NOTIF_CH_CALLS)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(openAndAnswerPending, true)
            .setAutoCancel(true)
            .setOngoing(true)
            .setDefaults(NotificationCompat.DEFAULT_VIBRATE)
            .setContentIntent(openAndAnswerPending)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Decline",
                declinePending
            )
            .addAction(
                android.R.drawable.ic_menu_call,
                "Answer",
                openAndAnswerPending
            )

        val notification = builder.build().apply {
            flags = flags or Notification.FLAG_INSISTENT
        }
        try {
            NotificationManagerCompat.from(context).notify(id, notification)
        } catch (_: SecurityException) {
        }
    }

    fun cancelCallNotification(context: Context, callId: String) {
        stopRingingTone()
        NotificationManagerCompat.from(context).cancel(callNotificationId(callId))
    }

    private fun startRingingTone(context: Context) {
        try {
            stopRingingTone()
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            val r = RingtoneManager.getRingtone(context.applicationContext, uri)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                r?.isLooping = true
            }
            r?.play()
            activeRingtone = r

            val vib = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            if (vib != null && vib.hasVibrator()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vib.vibrate(
                        VibrationEffect.createWaveform(
                            longArrayOf(0, 600, 400, 600, 400, 600),
                            -1
                        )
                    )
                } else {
                    @Suppress("DEPRECATION")
                    vib.vibrate(longArrayOf(0, 600, 400, 600, 400, 600), -1)
                }
            }
        } catch (_: Exception) {
        }
    }

    fun stopRingingTone() {
        try {
            activeRingtone?.stop()
        } catch (_: Exception) {
        }
        activeRingtone = null
    }
}

/**
 * Handles Decline button taps directly from the Android lock-screen / heads-up call notification
 * and restarts MelowRealtimeAlertService after device reboot or app update.
 */
class MelowNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action == MelowNotificationHelper.ACTION_DECLINE_CALL) {
            val callId = intent.getStringExtra(MelowNotificationHelper.EXTRA_CALL_ID) ?: return
            MelowNotificationHelper.cancelCallNotification(context, callId)
            try {
                if (FirebaseApp.getApps(context).isEmpty()) {
                    FirebaseApp.initializeApp(context)
                }
                val db = FirebaseFirestore.getInstance(FirebaseApp.getInstance(), "melow-game")
                db.collection("calls").document(callId).update("status", "declined")
            } catch (_: Exception) {
            }
        } else if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            MelowRealtimeAlertService.startIfLoggedIn(context)
        }
    }
}
