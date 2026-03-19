package com.music.player.data.auth

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

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

class AuthRepository(context: Context) {
    private val sessionManager = AuthSessionManager(context.applicationContext)
    private val authApi = SupabaseClient.authApi
    private val restApi = SupabaseClient.restApi

    private fun cacheUserId(userId: String) = sessionManager.cacheUserId(userId)
    private fun getCachedUserId(): String? = sessionManager.getCachedUserId()

    suspend fun signIn(email: String, password: String): AuthResult {
        return withContext(Dispatchers.IO) {
            try {
                val response = authApi.signIn(SignInRequest(email, password))
                val authResponse = response.body()

                if (!response.isSuccessful || authResponse == null) {
                    val errorBody = response.errorBody()?.string().orEmpty()
                    return@withContext AuthResult.Error(
                        when {
                            errorBody.contains("Invalid login credentials") -> "账号或密码错误"
                            errorBody.contains("Email not confirmed") -> "账号未验证，请查收邮件"
                            else -> "登录失败，请检查网络连接"
                        }
                    )
                }

                if (authResponse.error != null) {
                    return@withContext AuthResult.Error(
                        when {
                            authResponse.error.contains("Invalid") -> "账号或密码错误"
                            authResponse.error.contains("Email not confirmed") -> "账号未验证，请查收邮件"
                            else -> authResponse.error_description ?: authResponse.error
                        }
                    )
                }

                val token = authResponse.access_token ?: return@withContext AuthResult.Error("登录失败")
                val user = authResponse.user ?: return@withContext AuthResult.Error("登录失败")

                sessionManager.saveSession(
                    accessToken = token,
                    refreshToken = authResponse.refresh_token,
                    expiresInSeconds = authResponse.expires_in,
                    userId = user.id
                )

                AuthResult.Success(
                    UserProfile(
                        id = user.id,
                        email = user.email,
                        avatar_url = extractAvatarUrl(user)
                    )
                )
            } catch (e: Exception) {
                e.printStackTrace()
                AuthResult.Error("网络错误: ${e.message}")
            }
        }
    }

    suspend fun signUp(email: String, password: String): AuthResult {
        return withContext(Dispatchers.IO) {
            try {
                val response = authApi.signUp(AuthRequest(email, password))
                val authResponse = response.body()

                if (!response.isSuccessful || authResponse == null) {
                    return@withContext AuthResult.Error("该邮箱已被注册")
                }

                val token = authResponse.access_token ?: return@withContext AuthResult.Error("注册失败")
                val user = authResponse.user ?: return@withContext AuthResult.Error("注册失败")
                val authAvatarUrl = extractAvatarUrl(user)

                sessionManager.saveSession(
                    accessToken = token,
                    refreshToken = authResponse.refresh_token,
                    expiresInSeconds = authResponse.expires_in,
                    userId = user.id
                )

                createUserProfile(token, user.id, email, authAvatarUrl)

                AuthResult.Success(
                    UserProfile(
                        id = user.id,
                        email = user.email,
                        avatar_url = authAvatarUrl
                    )
                )
            } catch (e: Exception) {
                handleAuthError(e)
            }
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

    suspend fun getCurrentUser(): UserProfile? {
        return withContext(Dispatchers.IO) {
            try {
                val token = sessionManager.getValidAccessToken(authApi) ?: return@withContext null

                var response = authApi.getUser("Bearer $token")
                if (response.code() == 401) {
                    val refreshed = sessionManager.forceRefresh(authApi)
                    if (refreshed != null) {
                        response = authApi.getUser("Bearer $refreshed")
                    }
                }
                if (!response.isSuccessful || response.body() == null) {
                    if (response.code() == 401) sessionManager.clear()
                    return@withContext null
                }

                val user = response.body()!!
                val authAvatarUrl = extractAvatarUrl(user)
                if (getCachedUserId().isNullOrBlank()) {
                    cacheUserId(user.id)
                }

                val resolvedToken = sessionManager.getValidAccessToken(authApi) ?: token
                val profileResponse = restApi.getUsers(
                    token = "Bearer $resolvedToken",
                    id = "eq.${user.id}",
                    select = "id,email,username,nickname,signature,badge,avatar_url,created_at",
                    limit = 1
                )

                val profileRow = profileResponse.body()?.firstOrNull()
                if (profileRow == null) {
                    createUserProfile(token, user.id, user.email ?: "", authAvatarUrl)
                    return@withContext UserProfile(
                        id = user.id,
                        email = user.email,
                        avatar_url = authAvatarUrl
                    )
                }

                val profileAvatarUrl = (profileRow["avatar_url"] as? String)?.trim().orEmpty()
                UserProfile(
                    id = user.id,
                    email = profileRow["email"] as? String ?: user.email,
                    username = profileRow["username"] as? String,
                    nickname = profileRow["nickname"] as? String,
                    signature = profileRow["signature"] as? String,
                    badge = profileRow["badge"] as? String,
                    avatar_url = profileAvatarUrl.ifBlank { authAvatarUrl },
                    created_at = profileRow["created_at"] as? String
                )
            } catch (_: Exception) {
                null
            }
        }
    }

    fun isUserLoggedIn(): Boolean = sessionManager.isLoggedIn()

    private suspend fun createUserProfile(
        token: String,
        userId: String,
        email: String,
        avatarUrl: String? = null
    ) {
        try {
            val username = email.substringBefore("@")
            val profile = mutableMapOf<String, Any>(
                "id" to userId,
                "email" to email,
                "username" to username,
                "nickname" to username
            )
            avatarUrl?.takeIf { it.isNotBlank() }?.let { profile["avatar_url"] = it }
            restApi.insertUser(token = "Bearer $token", user = profile)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    suspend fun updateUserProfile(
        username: String?,
        nickname: String?,
        signature: String?,
        avatarUrl: String?
    ): AuthResult {
        return withContext(Dispatchers.IO) {
            try {
                val token = sessionManager.getValidAccessToken(authApi)
                    ?: return@withContext AuthResult.Error("未登录")
                val user = getCurrentUser()
                    ?: return@withContext AuthResult.Error("未登录")

                val updates = mutableMapOf<String, Any?>()
                username?.let { updates["username"] = it }
                nickname?.let { updates["nickname"] = it }
                signature?.let { updates["signature"] = it }
                avatarUrl?.let { updates["avatar_url"] = it }

                restApi.updateUser(
                    token = "Bearer $token",
                    id = "eq.${user.id}",
                    updates = updates
                )

                val updatedUser = getCurrentUser()
                if (updatedUser != null) {
                    AuthResult.Success(updatedUser)
                } else {
                    AuthResult.Error("更新失败")
                }
            } catch (e: Exception) {
                AuthResult.Error(e.message ?: "更新失败")
            }
        }
    }

    private fun handleAuthError(e: Exception): AuthResult.Error {
        val message = when {
            e.message?.contains("Invalid login credentials") == true -> "账号或密码错误"
            e.message?.contains("Email not confirmed") == true -> "账号未验证，请查收邮件"
            e.message?.contains("User already registered") == true -> "该邮箱已被注册"
            e.message?.contains("Password should be at least") == true -> "密码长度至少为 6 位"
            else -> e.message ?: "操作失败，请重试"
        }
        return AuthResult.Error(message)
    }

    private fun extractAvatarUrl(user: UserData): String? {
        val metadataAvatar = findAvatarInMap(user.user_metadata)
        if (metadataAvatar != null) return metadataAvatar

        return user.identities.orEmpty()
            .asSequence()
            .mapNotNull { identity -> findAvatarInMap(identity.identity_data) }
            .firstOrNull()
    }

    private fun findAvatarInMap(data: Map<String, Any?>?): String? {
        if (data.isNullOrEmpty()) return null
        return listOf("avatar_url", "avatarUrl", "picture", "avatar")
            .firstNotNullOfOrNull { key -> data[key] as? String }
            ?.trim()
            ?.takeIf { it.isNotBlank() }
    }
}
