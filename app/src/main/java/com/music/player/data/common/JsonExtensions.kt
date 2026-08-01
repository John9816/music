package com.music.player.data.common

import com.google.gson.JsonElement
import com.google.gson.JsonObject

/**
 * Shared JSON helper extensions used across repositories and parsers.
 * Eliminates duplication of [asJsonObjectOrNull], [obj], [str], [int], [long],
 * [stringOrNull], [intOrNull], [longOrNull], and [booleanOrFalse].
 */

fun JsonElement.asJsonObjectOrNull(): JsonObject? =
    takeIf { it.isJsonObject }?.asJsonObject

fun JsonObject.obj(name: String): JsonElement? =
    get(name)?.takeUnless { it.isJsonNull }

/** Basic string extraction — no HTML entity decoding. Use when the field cannot contain HTML. */
fun JsonObject.str(name: String): String =
    obj(name)?.let { runCatching { it.asString }.getOrNull() }.orEmpty().trim()

fun JsonObject.int(name: String, default: Int = 0): Int =
    obj(name)?.let { runCatching { it.asInt }.getOrNull() } ?: default

fun JsonObject.long(name: String, default: Long = 0L): Long =
    obj(name)?.let { runCatching { it.asLong }.getOrNull() } ?: default

fun JsonObject.stringOrNull(name: String): String? {
    val value = get(name) ?: return null
    if (value.isJsonNull || !value.isJsonPrimitive) return null
    return value.asString.trim().takeIf { it.isNotBlank() }
}

fun JsonObject.intOrNull(name: String): Int? =
    obj(name)?.let { runCatching { it.asInt }.getOrNull() }

fun JsonObject.longOrNull(name: String): Long? =
    obj(name)?.let { runCatching { it.asLong }.getOrNull() }

fun JsonObject.booleanOrFalse(name: String): Boolean =
    runCatching { get(name)?.asBoolean ?: false }.getOrDefault(false)
