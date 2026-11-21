package com.melowlabs.melow_tic_tac_toe

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.util.Base64
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "melow/audio_call"
        private const val REQ_RECORD_AUDIO = 4091
    }

    private var pendingMicResult: MethodChannel.Result? = null
    private var recorder: MediaRecorder? = null
    private var currentRecordFile: File? = null
    private var activePlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
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
                            @Suppress("DEPRECATION")
                            am.isSpeakerphoneOn = speaker
                            am.isMicrophoneMute = false
                        } else {
                            stopRecorderQuietly()
                            stopPlayerQuietly()
                            @Suppress("DEPRECATION")
                            am.isSpeakerphoneOn = false
                            am.mode = AudioManager.MODE_NORMAL
                        }
                        result.success(true)
                    }

                    "setSpeakerphone" -> {
                        val speaker = call.argument<Boolean>("speaker") ?: true
                        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        am.mode = AudioManager.MODE_IN_COMMUNICATION
                        @Suppress("DEPRECATION")
                        am.isSpeakerphoneOn = speaker
                        result.success(true)
                    }

                    "startRelayRecording" -> {
                        try {
                            stopRecorderQuietly()
                            val outFile = File(
                                cacheDir,
                                "melow_voice_${System.currentTimeMillis()}.m4a"
                            )
                            val mr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                MediaRecorder(this)
                            } else {
                                @Suppress("DEPRECATION")
                                MediaRecorder()
                            }
                            mr.setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
                            mr.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                            mr.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                            mr.setAudioSamplingRate(16000)
                            mr.setAudioEncodingBitRate(16000)
                            mr.setAudioChannels(1)
                            mr.setOutputFile(outFile.absolutePath)
                            mr.prepare()
                            mr.start()
                            recorder = mr
                            currentRecordFile = outFile
                            result.success(true)
                        } catch (e: Exception) {
                            stopRecorderQuietly()
                            result.error("REC_START_ERR", e.message, null)
                        }
                    }

                    "stopRelayRecording" -> {
                        try {
                            val mr = recorder
                            val file = currentRecordFile
                            recorder = null
                            currentRecordFile = null
                            if (mr != null) {
                                try {
                                    mr.stop()
                                } catch (_: Exception) {
                                }
                                try {
                                    mr.release()
                                } catch (_: Exception) {
                                }
                            }
                            if (file != null && file.exists() && file.length() > 200) {
                                val bytes = file.readBytes()
                                file.delete()
                                val b64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                                result.success(b64)
                            } else {
                                file?.delete()
                                result.success(null)
                            }
                        } catch (e: Exception) {
                            result.error("REC_STOP_ERR", e.message, null)
                        }
                    }

                    "playRelayAudio" -> {
                        val b64 = call.argument<String>("audioBase64")
                        val speaker = call.argument<Boolean>("speaker") ?: true
                        if (b64.isNullOrEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        try {
                            val bytes = Base64.decode(b64, Base64.DEFAULT)
                            val tmp = File(
                                cacheDir,
                                "melow_play_${System.currentTimeMillis()}.m4a"
                            )
                            tmp.writeBytes(bytes)
                            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            am.mode = AudioManager.MODE_IN_COMMUNICATION
                            @Suppress("DEPRECATION")
                            am.isSpeakerphoneOn = speaker

                            stopPlayerQuietly()
                            val mp = MediaPlayer()
                            mp.setAudioAttributes(
                                AudioAttributes.Builder()
                                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                                    .build()
                            )
                            mp.setDataSource(tmp.absolutePath)
                            mp.setOnCompletionListener { player ->
                                try {
                                    player.release()
                                } catch (_: Exception) {
                                }
                                tmp.delete()
                                if (activePlayer == player) activePlayer = null
                            }
                            mp.setOnErrorListener { player, _, _ ->
                                try {
                                    player.release()
                                } catch (_: Exception) {
                                }
                                tmp.delete()
                                if (activePlayer == player) activePlayer = null
                                true
                            }
                            mp.prepare()
                            mp.start()
                            activePlayer = mp
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PLAY_ERR", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun stopRecorderQuietly() {
        try {
            recorder?.stop()
        } catch (_: Exception) {
        }
        try {
            recorder?.release()
        } catch (_: Exception) {
        }
        recorder = null
        currentRecordFile?.delete()
        currentRecordFile = null
    }

    private fun stopPlayerQuietly() {
        try {
            activePlayer?.stop()
        } catch (_: Exception) {
        }
        try {
            activePlayer?.release()
        } catch (_: Exception) {
        }
        activePlayer = null
    }

    override fun onDestroy() {
        stopRecorderQuietly()
        stopPlayerQuietly()
        super.onDestroy()
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
        }
    }
}
