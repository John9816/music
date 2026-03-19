package com.music.player.data.auth

import retrofit2.Response
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST

interface SupabaseAuthApi {

    @POST("auth/v1/signup")
    suspend fun signUp(@Body request: AuthRequest): Response<AuthResponse>

    @POST("auth/v1/token?grant_type=password")
    suspend fun signIn(@Body request: SignInRequest): Response<AuthResponse>

    @POST("auth/v1/token?grant_type=refresh_token")
    suspend fun refreshToken(@Body request: RefreshTokenRequest): Response<AuthResponse>

    @POST("auth/v1/logout")
    suspend fun signOut(@Header("Authorization") token: String): Response<Unit>

    @GET("auth/v1/user")
    suspend fun getUser(@Header("Authorization") token: String): Response<UserData>
}

data class AuthRequest(
    val email: String,
    val password: String
)

data class SignInRequest(
    val email: String,
    val password: String
)

data class RefreshTokenRequest(
    val refresh_token: String
)

data class AuthResponse(
    val access_token: String?,
    val token_type: String?,
    val expires_in: Int?,
    val refresh_token: String?,
    val user: UserData?,
    val error: String?,
    val error_description: String?
)

data class UserData(
    val id: String,
    val email: String?,
    val created_at: String?,
    val user_metadata: Map<String, @JvmSuppressWildcards Any?>? = null,
    val identities: List<UserIdentity>? = null
)

data class UserIdentity(
    val identity_data: Map<String, @JvmSuppressWildcards Any?>? = null
)
