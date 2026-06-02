package me.oszkar.oto

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val multicastChannel = "me.oszkar.oto/multicast_lock"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, multicastChannel)
            .setMethodCallHandler(MulticastLockHandler(this))
    }
}
