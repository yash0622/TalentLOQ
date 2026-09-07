package com.example.talentloq

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableHighRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        enableHighRefreshRate()
    }

    /**
     * Dynamically queries the display hardware for its maximum supported refresh rate
     * (e.g. 90Hz, 120Hz, 144Hz) and unlocks the WindowManager to adapt to it.
     * Prevents OEM 60Hz frame lock on high refresh rate displays.
     */
    private fun enableHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                context.display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            }
            display?.let {
                val modes = it.supportedModes
                // Select the mode with the highest refresh rate supported by the display
                val highestRefreshRateMode = modes.maxByOrNull { mode -> mode.refreshRate }
                highestRefreshRateMode?.let { mode ->
                    val layoutParams = window.attributes
                    layoutParams.preferredDisplayModeId = mode.modeId
                    window.attributes = layoutParams
                }
            }
        }
    }
}
