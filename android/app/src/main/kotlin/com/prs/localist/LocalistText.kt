package com.prs.localist
import android.content.Context
import java.util.Locale
object LocalistText {
    fun choose(context: Context, fa: String, en: String): String {
        val language = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getString("flutter.app.language", "system")
        return if (language == "fa" || (language == "system" && Locale.getDefault().language == "fa")) fa else en
    }
}
