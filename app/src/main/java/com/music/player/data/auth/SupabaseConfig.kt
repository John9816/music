package com.music.player.data.auth

import android.util.Log

object SupabaseConfig {
    const val SUPABASE_URL = "https://vtvzpdupygvtytunrpdw.supabase.co"

    // 这是一个示例 key，需要从 Supabase Dashboard 获取真实的 anon key
    // 位置：Project Settings -> API -> anon public
    const val SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ0dnpwZHVweWd2dHl0dW5ycGR3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDAwMDAwMDAsImV4cCI6MjAxNTU3NjAwMH0.PLACEHOLDER_SIGNATURE"

    fun logConfig() {
        Log.d("SupabaseConfig", "URL: $SUPABASE_URL")
        Log.d("SupabaseConfig", "Key length: ${SUPABASE_ANON_KEY.length}")
    }
}
