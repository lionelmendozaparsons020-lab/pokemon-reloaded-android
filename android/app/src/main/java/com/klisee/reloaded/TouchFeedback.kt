package com.klisee.reloaded

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.SystemClock
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.HapticFeedbackConstants
import android.view.View

/** A short, non-repeating vibration on each touch control press. */
class TouchFeedback(private val context: Context, private val vibrator: Vibrator? = context.getSystemService(Vibrator::class.java)) {
    private var lastPulse = Long.MIN_VALUE
    val available: Boolean get() = vibrator?.hasVibrator() == true
    val supportsIntensity: Boolean get() = available && Build.VERSION.SDK_INT >= 30 &&
        vibrator!!.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_CLICK)

    fun press(view: View, appearance: TouchAppearance): Boolean {
        if (!appearance.haptics || !available) return false
        val now = SystemClock.uptimeMillis()
        // Do not fire a second pulse when simultaneous fingers hit the screen in the same frame.
        if (lastPulse != Long.MIN_VALUE && now - lastPulse < 25) return false
        lastPulse = now
        return runCatching {
            // A number of Samsung devices have a vibrator, but do not implement CLICK as a
            // composition primitive. Falling back to view haptics on the decor view can be silent.
            // Use the hardware vibrator for both paths; the requested strength stays meaningful.
            val effect = if (supportsIntensity) {
                VibrationEffect.startComposition()
                    .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, appearance.strength.scale)
                    .compose()
            } else {
                val amplitude = when (appearance.strength) {
                    TouchStrength.SOFT -> 90
                    TouchStrength.MEDIUM -> 160
                    TouchStrength.STRONG -> 255
                }
                VibrationEffect.createOneShot(25L, amplitude)
            }
            if (Build.VERSION.SDK_INT >= 33) {
                vibrator!!.vibrate(effect, VibrationAttributes.Builder().setUsage(VibrationAttributes.USAGE_TOUCH).build())
            } else {
                @Suppress("DEPRECATION")
                vibrator!!.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION).build())
            }
            true
        }.getOrElse {
            // Never crash the game due to a vendor-specific vibrator failure.
            view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
        }
    }
}
