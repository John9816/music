package com.music.player.data.auth

import retrofit2.Response
import okhttp3.ResponseBody
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST

interface SupabaseAuthApi {

    @POST("api/auth/register")
    suspend fun signUp(@Body request: AuthRequest): Response<ResponseBody>

    @POST("api/auth/login")
    suspend fun signIn(@Body request: SignInRequest): Response<ResponseBody>

    @POST("api/auth/refresh")
    suspend fun refreshToken(@Body request: RefreshTokenRequest): Response<ResponseBody>

    @POST("api/auth/logout")
    suspend fun signOut(@Header("Authorization") token: String): Response<Unit>

    @GET("api/user/me")
    suspend fun getUser(@Header("Authorization") token: String): Response<ResponseBody>
}

data class AuthRequest(
    val username: String,
    val email: String,
    val password: String
)

data class SignInRequest(
    val username: String,
    val password: String
)

data class RefreshTokenRequest(
    @com.google.gson.annotations.SerializedName("refresh_token")
    val refresh_token: String,
    // Some website backends expect camelCase.
    @com.google.gson.annotations.SerializedName("refreshToken")
    val refreshToken: String = refresh_token
)

data class AuthResponse(
    val token: String? = null,
    val tokenType: String? = null,
    val expiresInMinutes: Long? = null,
    val username: String? = null,
    val role: String? = null,
    val access_token: String? = null,
    val token_type: String? = null,
    val expires_in: Int? = null,
    val refresh_token: String? = null,
    val user: UserData? = null,
    val error: String? = null,
    val error_description: String? = null
)

data class UserData(
    val id: String,
    val username: String? = null,
    val nickname: String? = null,
    val signature: String? = null,
    val avatar_url: String? = null,
    val role: String? = null,
    val canManageSystemConfig: Boolean? = null,
    val email: String? = null,
    val created_at: String? = null,
    val user_metadata: Map<String, @JvmSuppressWildcards Any?>? = null,
    val identities: List<UserIdentity>? = null
)

data class UserIdentity(
    val identity_data: Map<String, @JvmSuppressWildcards Any?>? = null
)
