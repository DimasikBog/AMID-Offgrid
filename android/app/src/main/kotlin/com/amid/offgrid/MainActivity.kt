package com.amid.offgrid

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private var timeout: Runnable? = null
    private var events: EventChannel.EventSink? = null
    private var recognizer: SpeechRecognizer? = null
    private var session: Int? = null
    private var permissionResult: MethodChannel.Result? = null
    private var pendingLocale = "uk-UA"
    private val microphoneRequest = 6107

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        EventChannel(engine.dartExecutor.binaryMessenger, "com.amid.offgrid/emergency_voice")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { events = sink }
                override fun onCancel(arguments: Any?) { events = null; stopVoice() }
            })
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.amid.offgrid/emergency")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "composeSms" -> {
                        val number = call.argument<String>("number")
                        val body = call.argument<String>("body")
                        if (number != "112" || body == null || body.length > 2000) {
                            result.error("INVALID_SMS", "Invalid emergency message", null)
                        } else {
                            try {
                                startActivity(Intent(Intent.ACTION_SENDTO, Uri.fromParts("smsto", number, null)).putExtra("sms_body", body))
                                result.success(true)
                            } catch (_: android.content.ActivityNotFoundException) { result.success(false) }
                        }
                    }
                    "voiceStart" -> {
                        stopVoice()
                        val id = call.argument<Int>("session")
                        val locale = call.argument<String>("locale")
                        if (id == null || locale !in setOf("uk-UA", "cs-CZ", "en-US") || Build.VERSION.SDK_INT < 31 || !SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) {
                            result.success(false)
                        } else {
                            session = id; pendingLocale = locale!!
                            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                                permissionResult = result
                                requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), microphoneRequest)
                            } else { result.success(startVoice(id, pendingLocale)) }
                        }
                    }
                    "voiceCancel" -> {
                        if (call.argument<Int>("session") == session) stopVoice()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startVoice(id: Int, locale: String): Boolean {
        if (session != id || Build.VERSION.SDK_INT < 31 || !SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) return false
        return try {
            val listener = object : RecognitionListener {
                override fun onResults(results: Bundle?) {
                    val words = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                    if (session == id && words != null) events?.success(mapOf("session" to id, "words" to words, "final" to true))
                    if (session == id) stopVoice()
                }
                override fun onError(error: Int) {
                    if (session == id) events?.success(mapOf("session" to id, "error" to true))
                    if (session == id) stopVoice()
                }
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            }
            val local = SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
            recognizer = local
            local.setRecognitionListener(listener)
            local.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                })
            val deadline = Runnable {
                if (session == id) { events?.success(mapOf("session" to id, "error" to true)); stopVoice() }
            }
            timeout = deadline
            handler.postDelayed(deadline, 12000)
            true
        } catch (_: Exception) { stopVoice(); false }
    }

    private fun stopVoice() {
        session = null
        timeout?.let { handler.removeCallbacks(it) }; timeout = null
        val pending = permissionResult; permissionResult = null; pending?.success(false)
        val old = recognizer; recognizer = null
        old?.cancel(); old?.destroy()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == microphoneRequest) {
            val pending = permissionResult; permissionResult = null
            val id = session
            if (pending != null) pending.success(id != null && grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && startVoice(id, pendingLocale))
        }
    }
    override fun onPause() { stopVoice(); super.onPause() }
    override fun onDestroy() { stopVoice(); super.onDestroy() }
}
