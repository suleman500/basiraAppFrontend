package com.example.projctlitgudei

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // اسم القناة — لازم يطابق بالضبط النص بملف
    // native_detector_service.dart بجانب Dart.
    private val NATIVE_DETECTOR_CHANNEL = "basira/native_detector"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NATIVE_DETECTOR_CHANNEL
        ).setMethodCallHandler(NativeDetector())
    }
}