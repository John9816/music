package com.music.player.data.auth

import com.google.gson.JsonObject
import com.google.gson.JsonParser

internal data class AuthApiEnvelope(
    val code: Int,
    val message: String?,
    val data: AuthResponse?
)

internal object AuthResponseParser {
    fun parse(raw: String): AuthApiEnvelope? {
        if (raw.isBlank()) return null
        return runCatching {
            val root = JsonParser.parseString(raw).asJsonObject
            val data = root.objectOrNull("data") ?: root
            AuthApiEnvelope(
                code = root.intOrNull("code") ?: if (root.has("error")) -1 else 0,
                message = root.stringOrNull("message")
                    ?: root.stringOrNull("error_description")
                    ?: root.stringOrNull("error"),
                data = parseData(data)
            )
        }.getOrNull()
    }

    private fun parseData(data: JsonObject): AuthResponse {
        return AuthResponse(
            token = data.firstString("token", "accessToken", "access_token"),
            tokenType = data.firstString("tokenType", "token_type"),
            expiresInMinutes = data.longOrNull("expiresInMinutes"),
            username = data.stringOrNull("username"),
            role = data.stringOrNull("role"),
            access_token = data.firstString("access_token", "accessToken", "token"),
            expires_in = data.firstInt("expires_in", "expiresIn"),
            refresh_token = data.firstString("refresh_token", "refreshToken")
        )
    }

    private fun JsonObject.objectOrNull(name: String): JsonObject? {
        val value = get(name) ?: return null
        return value.takeIf { it.isJsonObject }?.asJsonObject
    }

    private fun JsonObject.firstString(vararg names: String): String? {
        return names.firstNotNullOfOrNull { stringOrNull(it) }
    }

    private fun JsonObject.firstInt(vararg names: String): Int? {
        return names.firstNotNullOfOrNull { intOrNull(it) }
    }

    private fun JsonObject.stringOrNull(name: String): String? {
        val value = get(name) ?: return null
        if (value.isJsonNull || !value.isJsonPrimitive) return null
        return value.asString.trim().takeIf { it.isNotBlank() }
    }

    private fun JsonObject.intOrNull(name: String): Int? {
        val value = get(name) ?: return null
        return runCatching { value.asInt }.getOrNull()
    }

    private fun JsonObject.longOrNull(name: String): Long? {
        val value = get(name) ?: return null
        return runCatching { value.asLong }.getOrNull()
    }
}
