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
                // 优先用 intent 传入的 gain，没有则读保存的值
                val intentGain = intent?.getIntExtra("gain", -1) ?: -1
                val gain = if (intentGain >= 0) intentGain else loadSavedGain()
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

    private fun loadSavedGain(): Int {
        return getSharedPreferences("volume_decay_prefs", MODE_PRIVATE)
            .getInt("last_gain", 40)
    }

    companion object {
        const val EXTRA_CUSTOM_ACTION = "custom_action"
    }
}
