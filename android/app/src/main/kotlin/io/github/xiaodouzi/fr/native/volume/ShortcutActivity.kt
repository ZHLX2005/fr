package io.github.xiaodouzi.fr.native.volume

import android.app.Activity
import android.content.Intent
import android.os.Build

class ShortcutActivity : Activity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        // customAction 通过 extra 传递，因为 intent action 固定为 VIEW
        val customAction = intent?.getStringExtra(EXTRA_CUSTOM_ACTION)

        when (customAction) {
            VolumeDecayService.ACTION_TURN_ON -> {
                val gain = intent?.getIntExtra("gain", 40) ?: 40
                startService(gain)
            }
            VolumeDecayService.ACTION_TURN_OFF -> {
                stopService()
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

    companion object {
        const val EXTRA_CUSTOM_ACTION = "custom_action"
    }
}
