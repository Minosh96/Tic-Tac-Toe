package com.melowlabs.melow_tic_tac_toe

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "melow/audio_call"
        private const val REQ_RECORD_AUDIO = 4091
    }

    private var pendingMicResult: MethodChannel.Result? = null

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

                    else -> result.notImplemented()
                }
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
        }
    }
}
