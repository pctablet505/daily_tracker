package com.dailytracker.daily_tracker

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.os.SystemClock
import android.view.WindowManager
import androidx.annotation.RequiresApi
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
        // Counts deep sleep and ignores the clock setting, so the app lock can
        // tell how long it was away even if the clock was set back.
        "elapsedRealtime" -> result.success(SystemClock.elapsedRealtime())
        "phoneLockIsCredentialOnly" ->
          result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
        "confirmDeviceCredential" -> {
          if (pendingCredentialResult != null) {
            result.error("BUSY", "Another credential check is running", null)
            return@setMethodCallHandler
          }
          val reason = call.argument<String>("reason")
            ?: "Unlock Daily Tracker with your phone lock"
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            confirmWithPrompt(reason, result)
          } else {
            confirmWithIntent(reason, result)
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  /** Android 11 and newer: the phone's PIN, pattern or password only, never a fingerprint. */
  @RequiresApi(Build.VERSION_CODES.R)
  private fun confirmWithPrompt(reason: String, result: MethodChannel.Result) {
    val credentialOnly = BiometricManager.Authenticators.DEVICE_CREDENTIAL
    val manager = getSystemService(BiometricManager::class.java)
    if (manager?.canAuthenticate(credentialOnly) != BiometricManager.BIOMETRIC_SUCCESS) {
      result.success(false)
      return
    }
    pendingCredentialResult = result
    BiometricPrompt.Builder(this)
      .setTitle("Daily Tracker")
      .setSubtitle(reason)
      .setAllowedAuthenticators(credentialOnly)
      .build()
      .authenticate(
        CancellationSignal(),
        mainExecutor,
        object : BiometricPrompt.AuthenticationCallback() {
          override fun onAuthenticationSucceeded(
            authResult: BiometricPrompt.AuthenticationResult?,
          ) = finishCredentialCheck(true)

          override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) =
            finishCredentialCheck(false)
        },
      )
  }

  /** Android 10 and older. This screen also takes a fingerprint, so the app hides
   *  "Use phone lock" there when fingerprint unlock is off. */
  private fun confirmWithIntent(reason: String, result: MethodChannel.Result) {
    val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
    @Suppress("DEPRECATION")
    val intent = km?.createConfirmDeviceCredentialIntent("Daily Tracker", reason)
    if (intent == null) {
      result.success(false)
    } else {
      pendingCredentialResult = result
      @Suppress("DEPRECATION")
      startActivityForResult(intent, REQUEST_CONFIRM_CREDENTIAL)
    }
  }

  private fun finishCredentialCheck(ok: Boolean) {
    val pending = pendingCredentialResult
    pendingCredentialResult = null
    pending?.success(ok)
  }

  @Deprecated("Deprecated in Java")
  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    super.onActivityResult(requestCode, resultCode, data)
    if (requestCode == REQUEST_CONFIRM_CREDENTIAL) {
      finishCredentialCheck(resultCode == Activity.RESULT_OK)
    }
  }

  companion object {
    private const val REQUEST_CONFIRM_CREDENTIAL = 4102
  }
}
