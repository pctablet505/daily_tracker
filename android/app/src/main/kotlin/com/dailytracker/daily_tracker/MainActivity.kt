package com.dailytracker.daily_tracker

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
  private var pendingCredentialResult: MethodChannel.Result? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "daily_tracker/platform",
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "setSecure" -> {
          val secure = call.argument<Boolean>("secure") ?: false
          if (secure) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
          } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
          }
          result.success(null)
        }
        "confirmDeviceCredential" -> {
          if (pendingCredentialResult != null) {
            result.error("BUSY", "Another credential check is running", null)
            return@setMethodCallHandler
          }
          val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
          @Suppress("DEPRECATION")
          val intent = km?.createConfirmDeviceCredentialIntent(
            "Daily Tracker",
            call.argument<String>("reason")
              ?: "Unlock Daily Tracker with your phone lock",
          )
          if (intent == null) {
            result.success(false)
          } else {
            pendingCredentialResult = result
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQUEST_CONFIRM_CREDENTIAL)
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  @Deprecated("Deprecated in Java")
  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    if (requestCode == REQUEST_CONFIRM_CREDENTIAL) {
      val pending = pendingCredentialResult
      pendingCredentialResult = null
      pending?.success(resultCode == Activity.RESULT_OK)
    }
  }

  companion object {
    private const val REQUEST_CONFIRM_CREDENTIAL = 4102
  }
}
