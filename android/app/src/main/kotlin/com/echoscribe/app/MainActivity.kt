package com.echoscribe.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import android.view.inputmethod.InputMethodManager
import androidx.activity.enableEdgeToEdge
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val floatingChannelName = "com.echoscribe.app/floating_dictation"
    private val keyboardChannelName = "com.echoscribe.app/keyboard_ime"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, keyboardChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncConfig" -> {
                        saveConfig(call.arguments)
                        result.success(null)
                    }
                    "getStatus" -> result.success(keyboardStatusMap())
                    "openInputMethodSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(null)
                    }
                    "openAppSettings" -> {
                        openAppSettings()
                        result.success(null)
                    }
                    "getVoiceMode" -> {
                        result.success(NativeDictationConfigStore(this).loadVoiceMode())
                    }
                    "setVoiceMode" -> {
                        val mode = call.arguments?.toString().orEmpty()
                        NativeDictationConfigStore(this).saveVoiceMode(mode)
                        notifyNativeConfigChanged()
                        result.success(NativeDictationConfigStore(this).loadVoiceMode())
                    }
                    "setKeyboardLayout" -> {
                        val layout = call.arguments?.toString().orEmpty()
                        NativeDictationConfigStore(this).saveKeyboardLayout(layout)
                        notifyNativeConfigChanged()
                        result.success(NativeDictationConfigStore(this).loadKeyboardLayout())
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, floatingChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "syncConfig" -> {
                        saveConfig(call.arguments)
                        result.success(null)
                    }
                    "getStatus" -> result.success(floatingStatusMap())
                    "openOverlaySettings" -> {
                        openOverlaySettings()
                        result.success(null)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(null)
                    }
                    "openAppSettings" -> {
                        openAppSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveConfig(arguments: Any?) {
        val args = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        NativeDictationConfigStore(this).save(args)
        notifyNativeConfigChanged()
    }

    private fun notifyNativeConfigChanged() {
        sendBroadcast(
            Intent(NativeDictationConfigStore.ACTION_CONFIG_CHANGED).setPackage(packageName),
        )
        sendBroadcast(
            Intent(FloatingDictationAccessibilityService.ACTION_CONFIG_CHANGED)
                .setPackage(packageName),
        )
    }

    private fun keyboardStatusMap(): Map<String, Any> {
        val store = NativeDictationConfigStore(this)
        val config = store.peek()
        return mapOf(
            "isAndroid" to true,
            "microphoneGranted" to microphoneGranted(),
            "imeEnabled" to isEchoScribeImeEnabled(),
            "voiceMode" to store.loadVoiceMode(),
            "keyboardLayout" to store.loadKeyboardLayout(),
            "configReady" to (config?.hasUsableProvider() == true),
            "provider" to (config?.provider ?: ""),
        )
    }

    private fun floatingStatusMap(): Map<String, Any> {
        val config = NativeDictationConfigStore(this).peek()
        return mapOf(
            "isAndroid" to true,
            "microphoneGranted" to microphoneGranted(),
            "overlayGranted" to Settings.canDrawOverlays(this),
            "accessibilityEnabled" to isAccessibilityServiceEnabled(),
            "configReady" to (config?.hasUsableProvider() == true),
            "enabled" to (config?.floatingEnabled != false),
            "provider" to (config?.provider ?: ""),
        )
    }

    private fun microphoneGranted(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun openOverlaySettings() {
        val uri = Uri.parse("package:$packageName")
        val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, uri)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun openAppSettings() {
        val uri = Uri.parse("package:$packageName")
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, uri)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun isEchoScribeImeEnabled(): Boolean {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
        if (imm.enabledInputMethodList.any { com.echoscribe.app.ime.ImeIds.matches(packageName, it.id) }) {
            return true
        }
        val enabled = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_INPUT_METHODS).orEmpty()
        return enabled.split(':').any { com.echoscribe.app.ime.ImeIds.matches(packageName, it) }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val expected = "$packageName/${FloatingDictationAccessibilityService::class.java.name}"
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        for (service in splitter) {
            if (service.equals(expected, ignoreCase = true)) return true
        }
        return false
    }
}
