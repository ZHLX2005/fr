package com.example.flutter_application_1.native.volume

import android.app.Activity
import android.content.Intent
import android.os.Build

class ShortcutActivity : Activity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        when (intent?.action) {
            VolumeDecayService.ACTION_TURN_ON -> {
                val gain = intent.getIntExtra("gain", 40)
                startService(gain)
                setResult(RESULT_OK)
            }
            VolumeDecayService.ACTION_TURN_OFF -> {
                stopService()
                setResult(RESULT_OK)
            }
        }
        finish()
    }

    private fun startService(gain: Int) {
        val serviceIntent = Intent(this, VolumeDecayService::class.java).apply {
            action = VolumeDecayService.ACTION_TURN_ON
            putExtra("gain", gain)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopService() {
        val serviceIntent = Intent(this, VolumeDecayService::class.java).apply {
            action = VolumeDecayService.ACTION_TURN_OFF
        }
        startService(serviceIntent)
    }
}
