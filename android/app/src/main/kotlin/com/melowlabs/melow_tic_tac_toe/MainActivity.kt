package com.melowlabs.melow_tic_tac_toe

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.RingtoneManager
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Base64
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "melow/audio_call"
        private const val NOTIF_CHANNEL = "melow/notifications"
        private const val REQ_RECORD_AUDIO = 4091
        private const val REQ_POST_NOTIFICATIONS = 4092
        private const val NOTIF_CH_MESSAGES = "melow_messages"
        private const val NOTIF_CH_CALLS = "melow_calls"
        private const val SAMPLE_RATE = 8000
        private const val FRAME_SAMPLES = 160 // 20ms at 8kHz
        private const val PACKET_FRAMES = 16 // 320ms per transmitted speech packet
        private const val HANGOVER_FRAMES = 30 // 600ms tail so words are never clipped
        private const val VAD_RMS_IDLE = 300.0
        private const val VAD_RMS_WHILE_PLAYING = 650.0
        private val MAGIC_MULAW = byteArrayOf('M'.code.toByte(), 'U'.code.toByte(), '0'.code.toByte(), '8'.code.toByte())
    }

    private var methodChannel: MethodChannel? = null
    private var pendingMicResult: MethodChannel.Result? = null
    private var pendingNotifResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Hands-free real-time full-duplex audio engine state
    private val relayRunning = AtomicBoolean(false)
    private val relayMuted = AtomicBoolean(false)
    private val lastPlaybackMs = AtomicLong(0L)
    private var captureThread: Thread? = null
    private var playbackExecutor: ExecutorService? = null
    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var echoCanceler: AcousticEchoCanceler? = null
    private var noiseSuppressor: NoiseSuppressor? = null
    private var autoGainControl: AutomaticGainControl? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        ensureNotificationChannels()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            result.success(true)
                        } else if (ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.POST_NOTIFICATIONS
                            ) == PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success(true)
                        } else {
                            pendingNotifResult?.success(false)
                            pendingNotifResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                REQ_POST_NOTIFICATIONS
                            )
                        }
                    }

                    "showMessageNotification" -> {
                        val notifId = call.argument<Int>("id") ?: 1001
                        val title = call.argument<String>("title") ?: "New Message"
                        val body = call.argument<String>("body") ?: ""
                        val count = call.argument<Int>("count") ?: 1
                        showMessageNotification(notifId, title, body, count)
                        result.success(true)
                    }

                    "showCallNotification" -> {
                        val callId = call.argument<String>("callId") ?: "call"
                        val callerName = call.argument<String>("callerName") ?: "Friend"
                        showCallNotification(callId, callerName)
                        result.success(true)
                    }

                    "cancelCallNotification" -> {
                        val callId = call.argument<String>("callId") ?: "call"
                        NotificationManagerCompat.from(this)
                            .cancel(callNotificationId(callId))
                        result.success(true)
                    }

                    "cancelMessageNotification" -> {
                        val notifId = call.argument<Int>("id") ?: 1001
                        NotificationManagerCompat.from(this).cancel(notifId)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestMicrophonePermission" -> {
                    if (ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(true)
                    } else {
                        pendingMicResult?.success(false)
                        pendingMicResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            REQ_RECORD_AUDIO
                        )
                    }
                }

                "setCommunicationAudio" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val speaker = call.argument<Boolean>("speaker") ?: true
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    if (enabled) {
                        am.mode = AudioManager.MODE_IN_COMMUNICATION
                        am.isMicrophoneMute = false
                        applySpeakerRouting(am, speaker)
                    } else {
                        stopFullDuplexEngine()
                        clearSpeakerRouting(am)
                        am.mode = AudioManager.MODE_NORMAL
                    }
                    result.success(true)
                }

                "setSpeakerphone" -> {
                    val speaker = call.argument<Boolean>("speaker") ?: true
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    am.mode = AudioManager.MODE_IN_COMMUNICATION
                    applySpeakerRouting(am, speaker)
                    result.success(true)
                }

                "startFullDuplexRelay" -> {
                    val speaker = call.argument<Boolean>("speaker") ?: true
                    val muted = call.argument<Boolean>("muted") ?: false
                    try {
                        startFullDuplexEngine(speaker, muted)
                        result.success(true)
                    } catch (e: Exception) {
                        stopFullDuplexEngine()
                        result.error("RELAY_START_ERR", e.message, null)
                    }
                }

                "setFullDuplexMuted" -> {
                    val muted = call.argument<Boolean>("muted") ?: false
                    relayMuted.set(muted)
                    result.success(true)
                }

                "playFullDuplexFrame" -> {
                    val b64 = call.argument<String>("audioBase64")
                    if (!b64.isNullOrEmpty() && relayRunning.get()) {
                        enqueueIncomingFrame(b64)
                    }
                    result.success(true)
                }

                "stopFullDuplexRelay" -> {
                    stopFullDuplexEngine()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun applySpeakerRouting(am: AudioManager, speaker: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val targetType = if (speaker) {
                    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                } else {
                    AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                }
                val device = am.availableCommunicationDevices.firstOrNull { it.type == targetType }
                if (device != null) {
                    am.setCommunicationDevice(device)
                } else if (!speaker) {
                    am.clearCommunicationDevice()
                }
            } catch (_: Exception) {
            }
        }
        @Suppress("DEPRECATION")
        am.isSpeakerphoneOn = speaker
    }

    private fun clearSpeakerRouting(am: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                am.clearCommunicationDevice()
            } catch (_: Exception) {
            }
        }
        @Suppress("DEPRECATION")
        am.isSpeakerphoneOn = false
    }

    private fun startFullDuplexEngine(speaker: Boolean, muted: Boolean) {
        stopFullDuplexEngine()

        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.RECORD_AUDIO
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            throw SecurityException("Microphone permission not granted")
        }

        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        am.isMicrophoneMute = false
        applySpeakerRouting(am, speaker)

        val minRecBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(FRAME_SAMPLES * 8)

        val rec = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            minRecBuf * 2
        )
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            throw IllegalStateException("AudioRecord failed to initialize")
        }

        val sessionId = rec.audioSessionId
        try {
            if (AcousticEchoCanceler.isAvailable()) {
                echoCanceler = AcousticEchoCanceler.create(sessionId)?.apply { enabled = true }
            }
        } catch (_: Exception) {
        }
        try {
            if (NoiseSuppressor.isAvailable()) {
                noiseSuppressor = NoiseSuppressor.create(sessionId)?.apply { enabled = true }
            }
        } catch (_: Exception) {
        }
        try {
            if (AutomaticGainControl.isAvailable()) {
                autoGainControl = AutomaticGainControl.create(sessionId)?.apply { enabled = true }
            }
        } catch (_: Exception) {
        }

        val minPlayBuf = AudioTrack.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(FRAME_SAMPLES * 8)

        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(minPlayBuf * 3)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()

        audioRecord = rec
        audioTrack = track
        relayMuted.set(muted)
        relayRunning.set(true)
        playbackExecutor = Executors.newSingleThreadExecutor()

        track.play()
        rec.startRecording()

        captureThread = Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO)
            val pcmFrame = ShortArray(FRAME_SAMPLES)
            val packetOut = ByteArrayOutputStream(FRAME_SAMPLES * PACKET_FRAMES + 8)
            var framesInPacket = 0
            var hangoverLeft = 0
            var wasSpeaking = false

            fun resetPacket() {
                packetOut.reset()
                packetOut.write(MAGIC_MULAW)
                framesInPacket = 0
            }

            fun flushPacket() {
                if (framesInPacket <= 0) return
                val bytes = packetOut.toByteArray()
                val durMs = framesInPacket * 20
                resetPacket()
                val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                mainHandler.post {
                    if (relayRunning.get()) {
                        methodChannel?.invokeMethod(
                            "onFullDuplexFrame",
                            mapOf("audioBase64" to b64, "durationMs" to durMs)
                        )
                    }
                }
            }

            fun notifySpeaking(speaking: Boolean) {
                if (speaking == wasSpeaking) return
                wasSpeaking = speaking
                mainHandler.post {
                    if (relayRunning.get()) {
                        methodChannel?.invokeMethod("onLocalSpeaking", speaking)
                    }
                }
            }

            resetPacket()

            while (relayRunning.get()) {
                val read = try {
                    rec.read(pcmFrame, 0, FRAME_SAMPLES)
                } catch (_: Exception) {
                    -1
                }
                if (read <= 0) continue

                if (relayMuted.get()) {
                    hangoverLeft = 0
                    resetPacket()
                    notifySpeaking(false)
                    continue
                }

                var sumSq = 0.0
                for (i in 0 until read) {
                    val v = pcmFrame[i].toDouble()
                    sumSq += v * v
                }
                val rms = sqrt(sumSq / read)
                val remoteRecentlyActive =
                    (System.currentTimeMillis() - lastPlaybackMs.get()) < 350L
                val threshold = if (remoteRecentlyActive) VAD_RMS_WHILE_PLAYING else VAD_RMS_IDLE

                if (rms >= threshold) {
                    hangoverLeft = HANGOVER_FRAMES
                }

                if (hangoverLeft > 0) {
                    hangoverLeft--
                    notifySpeaking(true)
                    for (i in 0 until read) {
                        packetOut.write(linearToMuLaw(pcmFrame[i]).toInt() and 0xFF)
                    }
                    framesInPacket++
                    if (framesInPacket >= PACKET_FRAMES) {
                        flushPacket()
                    }
                } else {
                    if (framesInPacket >= 3) {
                        flushPacket()
                    } else if (framesInPacket > 0) {
                        resetPacket()
                    }
                    notifySpeaking(false)
                }
            }
        }, "MelowVoiceCapture").apply { start() }
    }

    private fun enqueueIncomingFrame(b64: String) {
        val exec = playbackExecutor ?: return
        val track = audioTrack ?: return
        exec.execute {
            if (!relayRunning.get()) return@execute
            try {
                val raw = Base64.decode(b64, Base64.DEFAULT)
                if (raw.size <= 4) return@execute
                // Verify MU08 8kHz G.711 u-law magic header
                if (raw[0] != MAGIC_MULAW[0] ||
                    raw[1] != MAGIC_MULAW[1] ||
                    raw[2] != MAGIC_MULAW[2] ||
                    raw[3] != MAGIC_MULAW[3]
                ) {
                    return@execute
                }
                val sampleCount = raw.size - 4
                val pcm = ShortArray(sampleCount)
                for (i in 0 until sampleCount) {
                    pcm[i] = muLawToLinear(raw[i + 4])
                }
                lastPlaybackMs.set(System.currentTimeMillis())
                track.write(pcm, 0, pcm.size)
                lastPlaybackMs.set(System.currentTimeMillis())
            } catch (_: Exception) {
            }
        }
    }

    private fun stopFullDuplexEngine() {
        relayRunning.set(false)
        try {
            captureThread?.join(250)
        } catch (_: Exception) {
        }
        captureThread = null

        try {
            playbackExecutor?.shutdownNow()
        } catch (_: Exception) {
        }
        playbackExecutor = null

        try {
            echoCanceler?.release()
        } catch (_: Exception) {
        }
        echoCanceler = null

        try {
            noiseSuppressor?.release()
        } catch (_: Exception) {
        }
        noiseSuppressor = null

        try {
            autoGainControl?.release()
        } catch (_: Exception) {
        }
        autoGainControl = null

        try {
            audioRecord?.stop()
        } catch (_: Exception) {
        }
        try {
            audioRecord?.release()
        } catch (_: Exception) {
        }
        audioRecord = null

        try {
            audioTrack?.pause()
            audioTrack?.flush()
            audioTrack?.stop()
        } catch (_: Exception) {
        }
        try {
            audioTrack?.release()
        } catch (_: Exception) {
        }
        audioTrack = null
    }

    // Standard ITU-T G.711 u-law encoder (16-bit signed linear PCM -> 8-bit u-law)
    private fun linearToMuLaw(sample: Short): Byte {
        var pcm = sample.toInt()
        val mask: Int
        if (pcm < 0) {
            pcm = -pcm
            mask = 0x7F
        } else {
            mask = 0xFF
        }
        if (pcm > 32635) pcm = 32635
        pcm += 132

        var seg = 0
        var shifted = pcm shr 7
        while (shifted > 1 && seg < 7) {
            shifted = shifted shr 1
            seg++
        }
        val mantissa = (pcm shr (seg + 3)) and 0x0F
        val uval = (seg shl 4) or mantissa
        return (uval xor mask).toByte()
    }

    // Standard ITU-T G.711 u-law decoder (8-bit u-law -> 16-bit signed linear PCM)
    private fun muLawToLinear(uByte: Byte): Short {
        val u = uByte.toInt().inv() and 0xFF
        val sign = u and 0x80
        val exponent = (u shr 4) and 0x07
        val mantissa = u and 0x0F
        var sample = ((mantissa shl 3) + 132) shl exponent
        sample -= 132
        return (if (sign != 0) -sample else sample).toShort()
    }

    override fun onDestroy() {
        stopFullDuplexEngine()
        super.onDestroy()
    }

    private fun ensureNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val msgChannel = NotificationChannel(
            NOTIF_CH_MESSAGES,
            "Chat Messages",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Notifications for new friend chat messages"
            enableVibration(true)
            setShowBadge(true)
        }
        nm.createNotificationChannel(msgChannel)

        val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val callAudioAttr = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val callChannel = NotificationChannel(
            NOTIF_CH_CALLS,
            "Voice Calls",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Incoming voice calls from friends"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 450, 250, 450)
            setSound(ringtoneUri, callAudioAttr)
            setShowBadge(true)
        }
        nm.createNotificationChannel(callChannel)
    }

    private fun canPostNotifications(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
    }

    private fun createOpenAppPendingIntent(reqCode: Int): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getActivity(this, reqCode, intent, flags)
    }

    private fun showMessageNotification(notifId: Int, title: String, body: String, count: Int) {
        if (!canPostNotifications()) return
        ensureNotificationChannels()
        val builder = NotificationCompat.Builder(this, NOTIF_CH_MESSAGES)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setNumber(count)
            .setContentIntent(createOpenAppPendingIntent(notifId))
        try {
            NotificationManagerCompat.from(this).notify(notifId, builder.build())
        } catch (_: SecurityException) {
        }
    }

    private fun callNotificationId(callId: String): Int =
        200000 + (callId.hashCode() and 0x7FFF)

    private fun showCallNotification(callId: String, callerName: String) {
        if (!canPostNotifications()) return
        ensureNotificationChannels()
        val id = callNotificationId(callId)
        val builder = NotificationCompat.Builder(this, NOTIF_CH_CALLS)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Incoming Voice Call")
            .setContentText("$callerName is calling you on Melow Tic Tac Toe")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setAutoCancel(true)
            .setDefaults(NotificationCompat.DEFAULT_VIBRATE)
            .setContentIntent(createOpenAppPendingIntent(id))
        try {
            NotificationManagerCompat.from(this).notify(id, builder.build())
        } catch (_: SecurityException) {
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_RECORD_AUDIO) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingMicResult?.success(granted)
            pendingMicResult = null
        } else if (requestCode == REQ_POST_NOTIFICATIONS) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotifResult?.success(granted)
            pendingNotifResult = null
        }
    }
}
