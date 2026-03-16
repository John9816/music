package com.music.player.data.auth

import android.content.Context
import android.content.SharedPreferences
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
    private val prefs: SharedPreferences = context.getSharedPreferences("auth_prefs", Context.MODE_PRIVATE)
    private val authApi = SupabaseClient.authApi
    private val restApi = SupabaseClient.restApi

    private fun saveSession(token: String, userId: String?) {
        prefs.edit()
            .putString("access_token", token)
            .putString("user_id", userId)
            .apply()
    }

    private fun getToken(): String? {
        return prefs.getString("access_token", null)
    }

    private fun getCachedUserId(): String? {
        return prefs.getString("user_id", null)
    }

    private fun clearToken() {
        prefs.edit()
            .remove("access_token")
            .remove("user_id")
            .apply()
    }

    suspend fun signIn(email: String, password: String): AuthResult {
        return withContext(Dispatchers.IO) {
            try {
                val response = authApi.signIn(SignInRequest(email, password))

                if (response.isSuccessful && response.body() != null) {
                    val authResponse = response.body()!!

                    // 检查是否有错误
                    if (authResponse.error != null) {
                        return@withContext AuthResult.Error(
                            when {
                                authResponse.error.contains("Invalid") -> "账号或密码错误"
                                authResponse.error.contains("Email not confirmed") -> "账号未验证，请查收邮件"
                                else -> authResponse.error_description ?: authResponse.error
                            }
                        )
                    }

                    val token = authResponse.access_token

                    if (token != null) {
                        val user = authResponse.user
                        if (user != null) {
                            saveSession(token, user.id)
                            saveSession(token, user.id)
                            AuthResult.Success(
                                UserProfile(
                                    id = user.id,
                                    email = user.email
                                )
                            )
                        } else {
                            AuthResult.Error("登录失败")
                        }
                    } else {
                        AuthResult.Error("登录失败")
                    }
                } else {
                    // 解析错误响应
                    val errorBody = response.errorBody()?.string()
                    AuthResult.Error(
                        when {
                            errorBody?.contains("Invalid login credentials") == true -> "账号或密码错误"
                            errorBody?.contains("Email not confirmed") == true -> "账号未验证，请查收邮件"
                            else -> "登录失败，请检查网络连接"
                        }
                    )
                }
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

                if (response.isSuccessful && response.body() != null) {
                    val authResponse = response.body()!!
                    val token = authResponse.access_token

                    if (token != null) {
                        // session will be saved when user is available
                        val user = authResponse.user
                        if (user != null) {
                            // 创建用户资料
                            createUserProfile(token, user.id, email)

                            AuthResult.Success(
                                UserProfile(
                                    id = user.id,
                                    email = user.email
                                )
                            )
                        } else {
                            AuthResult.Error("注册失败")
                        }
                    } else {
                        AuthResult.Error("注册失败")
                    }
                } else {
                    AuthResult.Error("该邮箱已被注册")
                }
            } catch (e: Exception) {
                handleAuthError(e)
            }
        }
    }

    suspend fun signOut() {
        withContext(Dispatchers.IO) {
            try {
                val token = getToken()
                if (token != null) {
                    authApi.signOut("Bearer $token")
                }
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                clearToken()
            }
        }
    }

    suspend fun getCurrentUser(): UserProfile? {
        return withContext(Dispatchers.IO) {
            try {
                val token = getToken() ?: return@withContext null

                val response = authApi.getUser("Bearer $token")
                if (response.isSuccessful && response.body() != null) {
                    val user = response.body()!!
                    if (getCachedUserId().isNullOrBlank()) {
                        saveSession(token, user.id)
                    }

                    val profileResponse = restApi.getUsers(
                        token = "Bearer $token",
                        id = "eq.${user.id}",
                        select = "id,email,username,nickname,signature,badge,avatar_url,created_at",
                        limit = 1
                    )

                    val profileRow = profileResponse.body()?.firstOrNull()
                    if (profileRow == null) {
                        createUserProfile(token, user.id, user.email ?: "")
                        return@withContext UserProfile(id = user.id, email = user.email)
                    }

                    UserProfile(
                        id = user.id,
                        email = profileRow["email"] as? String ?: user.email,
                        username = profileRow["username"] as? String,
                        nickname = profileRow["nickname"] as? String,
                        signature = profileRow["signature"] as? String,
                        badge = profileRow["badge"] as? String,
                        avatar_url = profileRow["avatar_url"] as? String,
                        created_at = profileRow["created_at"] as? String
                    )
                } else {
                    null
                }
            } catch (e: Exception) {
                null
            }
        }
    }

    fun isUserLoggedIn(): Boolean {
        return getToken() != null
    }

    private suspend fun createUserProfile(token: String, userId: String, email: String) {
        try {
            val username = email.substringBefore("@")
            val profile = mapOf(
                "id" to userId,
                "email" to email,
                "username" to username,
                "nickname" to username
            )

            restApi.insertUser(token = "Bearer $token", user = profile)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    suspend fun updateUserProfile(username: String?, nickname: String?, signature: String?, avatarUrl: String?): AuthResult {
        return withContext(Dispatchers.IO) {
            try {
                val token = getToken() ?: return@withContext AuthResult.Error("未登录")
                val user = getCurrentUser() ?: return@withContext AuthResult.Error("未登录")

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
}
