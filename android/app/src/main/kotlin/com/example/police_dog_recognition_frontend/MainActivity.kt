package com.example.police_dog_recognition_frontend

import com.example.police_dog_recognition_frontend.bridge.BackendBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        BackendBridge(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
