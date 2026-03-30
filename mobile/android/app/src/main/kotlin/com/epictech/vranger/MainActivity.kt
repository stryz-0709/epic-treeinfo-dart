package com.epictech.vranger

import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(
			flutterEngine.dartExecutor.binaryMessenger,
			"com.epictech.vranger/app_launcher"
		).setMethodCallHandler { call, result ->
			when (call.method) {
				"openAppByPackage" -> {
					val packageName = call.argument<String>("packageName")

					if (packageName.isNullOrBlank()) {
						result.success(false)
						return@setMethodCallHandler
					}

					val launchIntent = applicationContext.packageManager
						.getLaunchIntentForPackage(packageName)

					if (launchIntent == null) {
						result.success(false)
						return@setMethodCallHandler
					}

					launchIntent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)

					try {
						startActivity(launchIntent)
						result.success(true)
					} catch (_: Exception) {
						result.success(false)
					}
				}

				else -> result.notImplemented()
			}
		}
	}
}
