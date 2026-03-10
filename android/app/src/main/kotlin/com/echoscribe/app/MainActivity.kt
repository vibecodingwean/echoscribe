package com.echoscribe.app

import android.content.res.Configuration
import android.os.Bundle
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Aktiviert Edge-to-Edge (Content hinter Systemleisten zeichnen)
        WindowCompat.setDecorFitsSystemWindows(window, false)

        // Kontrast der Icons abhängig vom Hell/Dunkel-Modus setzen
        val isDark =
            (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val insets = WindowInsetsControllerCompat(window, window.decorView)
        insets.isAppearanceLightStatusBars = !isDark
        insets.isAppearanceLightNavigationBars = !isDark
    }
}

