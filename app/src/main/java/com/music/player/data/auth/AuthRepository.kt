package com.music.player.data.auth

import android.content.Context
import android.net.Uri
import android.util.Log
import com.music.player.ui.util.absoluteApiUrl
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.ResponseBody
import org.json.JSONObject
import retrofit2.Response
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

data class UserProfile(
    val id: String,
    val email: String? = null,
    val username: String? = null,
    val nickname: String? = null,
    val signature: String? = null,
    val badge: String? = null,
    val avatar_url: String? = null,
    val created_at: String? = null
)

sealed class AuthResult {
    data class Success(val user: UserProfile) : AuthResult()
    data class Error(val message: String) : AuthResult()
}

private data class WebsiteApiResponse<T>(
    val code: Int,
    val message: String?,
    val data: T?
)

class AuthRepository(context: Context) {
    private val sessionManager = AuthSessionManager(context.applicationContext)
    private val profilePreferences = UserProfilePreferences(context.applicationContext)
    private val authApi = SupabaseClient.authApi

    suspend fun signIn(username: String, password: String): AuthResult = withContext(Dispatchers.IO) {
        try {
            val loginName = username.trim()
            val response = authApi.signIn(SignInRequest(loginName, password))
            val rawBody = response.body()?.string().orEmpty()
            val apiResponse = parseAuthApiResponse(rawBody)
            val authResponse = apiResponse?.data

            if (!response.isSuccessful || apiResponse == null || apiResponse.code != 0 || authResponse == null) {
                return@withContext AuthResult.Error(signInErrorMessage(response, apiResponse?.message))
            }

            val token = authResponse.token ?: authResponse.access_token
                ?: return@withContext AuthResult.Error("Login failed")
            val userId = sessionManager.syncUserIdFromAccessToken(token)
            val expiresInSeconds = authResponse.expires_in
                ?: authResponse.expiresInMinutes?.let { (it * 60L).toInt() }

            sessionManager.saveSession(
                accessToken = token,
                refreshToken = authResponse.refresh_token,
                expiresInSeconds = expiresInSeconds,
                userId = userId
            )

            val currentUser = getCurrentUser()
            AuthResult.Success(
                currentUser ?: UserProfile(
                    id = userId ?: authResponse.username ?: loginName,
                    username = authResponse.username ?: loginName,
                    nickname = authResponse.username ?: loginName,
                    badge = authResponse.role
                )
            )
        } catch (e: Exception) {
            AuthResult.Error(exceptionToAuthMessage(e))
        }
    }

    /**
     * Backend requires both [username] (login key, 3–50 chars) and [email].
     */
    suspend fun signUp(username: String, email: String, password: String): AuthResult = withContext(Dispatchers.IO) {
        try {
            val name = username.trim()
            val mail = email.trim()
            val response = authApi.signUp(AuthRequest(name, mail, password))
            val rawBody = response.body()?.string().orEmpty()
            val apiResponse = parseAuthApiResponse(rawBody)
            val authResponse = apiResponse?.data

            if (!response.isSuccessful || apiResponse == null || apiResponse.code != 0 || authResponse == null) {
                val rawError = runCatching { response.errorBody()?.string().orEmpty() }.getOrDefault("")
                return@withContext AuthResult.Error(
                    apiResponse?.message
                        ?: extractServerErrorMessage(rawError)
                        ?: extractServerErrorMessage(rawBody)
                        ?: "Register failed"
                )
            }

            val token = authResponse.token ?: authResponse.access_token
                ?: return@withContext AuthResult.Error("Register failed")
            val userId = sessionManager.syncUserIdFromAccessToken(token)
            val expiresInSeconds = authResponse.expires_in
                ?: authResponse.expiresInMinutes?.let { (it * 60L).toInt() }

            sessionManager.saveSession(
                accessToken = token,
                refreshToken = authResponse.refresh_token,
                expiresInSeconds = expiresInSeconds,
                userId = userId
            )

            val currentUser = getCurrentUser()
            AuthResult.Success(
                currentUser ?: UserProfile(
                    id = userId ?: authResponse.username ?: name,
                    email = mail,
                    username = authResponse.username ?: name,
                    nickname = authResponse.username ?: name,
                    badge = authResponse.role
                )
            )
        } catch (e: Exception) {
            AuthResult.Error(exceptionToAuthMessage(e))
        }
    }

    suspend fun signOut() {
        withContext(Dispatchers.IO) {
            val token = runCatching { sessionManager.getValidAccessToken(authApi) }.getOrNull()
            sessionManager.clear()
            runCatching {
                if (!token.isNullOrBlank()) {
                    authApi.signOut("Bearer $token")
                }
            }
        }
    }

    suspend fun getCurrentUser(): UserProfile? = withContext(Dispatchers.IO) {
        try {
            var token = sessionManager.getValidAccessToken(authApi) ?: return@withContext null
            var response = authApi.getUser("Bearer $token")
            if (response.code() == 401) {
                when (val refresh = sessionManager.forceRefresh(authApi)) {
                    is TokenRefreshResult.Success -> {
                        token = refresh.accessToken
                        response = authApi.getUser("Bearer $token")
                        // Only invalidate when refresh succeeded but token still rejected,
                        // or there is no refresh token to recover with.
                        if (response.code() == 401) sessionManager.invalidateSession()
                    }
                    TokenRefreshResult.InvalidSession -> Unit // already cleared
                    TokenRefreshResult.MissingRefreshToken -> {
                        // Access token rejected and no way to renew — true logout.
                        sessionManager.invalidateSession()
                    }
                    // Network / missing refresh route: keep local session for next launch.
                    TokenRefreshResult.TransientFailure -> Unit
                }
            }
            val apiResponse = parseUserApiResponse(response.body()?.string().orEmpty())
            if (!response.isSuccessful || apiResponse == null || apiResponse.code != 0) {
                return@withContext null
            }

            val user = apiResponse.data ?: return@withContext null
            sessionManager.cacheUserId(user.id)
            // Local prefs can override nickname/signature/avatar after client-side edits.
            profilePreferences.applyTo(
                UserProfile(
                    id = user.id,
                    email = user.email,
                    username = user.username,
                    nickname = user.nickname?.takeIf { it.isNotBlank() } ?: user.username,
                    signature = user.signature,
                    badge = user.role,
                    avatar_url = user.avatar_url,
                    created_at = user.created_at
                )
            )
        } catch (ce: CancellationException) {
            throw ce
        } catch (e: IOException) {
            // 网络问题（超时、无网络、连接中断）不代表用户未登录，仅记录后返回 null
            Log.w(TAG, "getCurrentUser network error: ${e.javaClass.simpleName}: ${e.message}")
            null
        } catch (e: Exception) {
            Log.e(TAG, "getCurrentUser unexpected error", e)
            null
        }
    }

    fun isUserLoggedIn(): Boolean = sessionManager.isLoggedIn()

    suspend fun updateUserProfile(
        username: String?,
        nickname: String?,
        signature: String?,
        avatarUrl: String?
    ): AuthResult = withContext(Dispatchers.IO) {
        val user = getCurrentUser() ?: return@withContext AuthResult.Error("Not signed in")
        AuthResult.Success(profilePreferences.save(user, username, nickname, signature, avatarUrl))
    }

    suspend fun uploadAvatarImage(imageUri: Uri): AuthResult = withContext(Dispatchers.IO) {
        val user = getCurrentUser() ?: return@withContext AuthResult.Error("Not signed in")
        runCatching { profilePreferences.saveAvatar(user, imageUri) }
            .fold(
                onSuccess = { AuthResult.Success(it) },
                onFailure = { AuthResult.Error(it.message ?: "头像更新失败") }
            )
    }

    private fun parseAuthApiResponse(raw: String): WebsiteApiResponse<AuthResponse>? {
        val parsed = AuthResponseParser.parse(raw) ?: return null
        return WebsiteApiResponse(parsed.code, parsed.message, parsed.data)
    }

    private fun parseUserApiResponse(raw: String): WebsiteApiResponse<UserData>? {
        return parseWebsiteResponse(raw) { data ->
            // Backend field names vary across website / Supabase-shaped payloads.
            val meta = data.optJSONObject("user_metadata")
            val avatarRaw = data.firstNonBlank(
                "avatar_url", "avatarUrl", "avatar", "avatar_path", "headImg", "headimgurl"
            ) ?: meta?.firstNonBlank("avatar_url", "avatarUrl", "avatar")
            // Website returns path-only avatars: "/api/v1/user/avatar/….png"
            val avatar = absoluteApiUrl(avatarRaw) ?: avatarRaw

            UserData(
                id = data.firstNonBlank("id", "userId", "user_id").orEmpty(),
                username = data.firstNonBlank("username", "userName", "name"),
                nickname = data.firstNonBlank("nickname", "nickName", "displayName", "display_name")
                    ?: meta?.firstNonBlank("nickname", "full_name", "name"),
                signature = data.firstNonBlank("signature", "bio", "description", "intro"),
                avatar_url = avatar,
                role = data.firstNonBlank("role", "badge"),
                canManageSystemConfig = data.optBooleanOrNull("canManageSystemConfig"),
                email = data.firstNonBlank("email")
                    ?: meta?.firstNonBlank("email"),
                created_at = data.firstNonBlank("createdAt", "created_at")
            )
        }
    }

    private fun JSONObject.firstNonBlank(vararg names: String): String? {
        for (name in names) {
            val value = optString(name).trim()
            if (value.isNotBlank() && value != "null") return value
        }
        return null
    }

    private fun <T> parseWebsiteResponse(raw: String, parseData: (JSONObject) -> T): WebsiteApiResponse<T>? {
        if (raw.isBlank()) return null
        return runCatching {
            val root = JSONObject(raw)
            val dataObject = root.optJSONObject("data")
            WebsiteApiResponse(
                code = root.optInt("code", -1),
                message = root.optString("message").takeIf { it.isNotBlank() },
                data = dataObject?.let(parseData)
            )
        }.getOrNull()
    }

    private fun JSONObject.optLongOrNull(name: String): Long? {
        return if (has(name) && !isNull(name)) optLong(name) else null
    }

    private fun JSONObject.optBooleanOrNull(name: String): Boolean? {
        return if (has(name) && !isNull(name)) optBoolean(name) else null
    }

    private fun signInErrorMessage(response: Response<ResponseBody>, serverMessage: String?): String {
        val rawError = runCatching { response.errorBody()?.string().orEmpty() }.getOrDefault("")
        val extractedMessage = serverMessage ?: extractServerErrorMessage(rawError)

        return when {
            rawError.contains("Invalid username or password", ignoreCase = true) ||
                extractedMessage?.contains("Invalid username or password", ignoreCase = true) == true ->
                "账号或密码错误（请使用注册时的用户名登录，不是邮箱）"
            response.code() == 429 -> "请求过于频繁，请稍后再试"
            response.code() in 500..599 -> "登录服务暂时不可用，请稍后再试"
            extractedMessage != null -> "登录失败: $extractedMessage"
            else -> "登录失败 (HTTP ${response.code()})"
        }
    }

    private fun extractServerErrorMessage(rawError: String): String? {
        if (rawError.isBlank()) return null
        return runCatching {
            JSONObject(rawError).let { json ->
                sequenceOf(
                    json.optString("msg"),
                    json.optString("error_description"),
                    json.optString("error"),
                    json.optString("message")
                ).firstOrNull { it.isNotBlank() }
            }
        }.getOrNull() ?: rawError
    }

    private fun exceptionToAuthMessage(e: Exception): String {
        return when (e) {
            is UnknownHostException -> "无法连接登录服务，请检查当前网络"
            is SocketTimeoutException -> "连接登录服务超时，请稍后再试"
            is IOException -> "连接登录服务失败，请检查当前网络"
            else -> "登录失败: ${e.message ?: e.javaClass.simpleName}"
        }
    }

    private companion object {
        const val TAG = "AuthRepository"
    }
}
