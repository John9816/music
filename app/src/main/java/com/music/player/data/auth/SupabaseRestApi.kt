package com.music.player.data.auth

import okhttp3.RequestBody
import retrofit2.Response
import retrofit2.http.*

interface SupabaseRestApi {

    @GET("rest/v1/users")
    suspend fun getUsers(
        @Header("Authorization") token: String,
        @Query("id") id: String,
        @Query("select") select: String = "*",
        @Query("limit") limit: Int = 1
    ): Response<List<Map<String, Any?>>>

    @POST("rest/v1/users")
    suspend fun insertUser(
        @Header("Authorization") token: String,
        @Header("Prefer") prefer: String = "return=minimal",
        @Body user: Map<String, Any?>
    ): Response<List<Map<String, Any?>>>

    @PATCH("rest/v1/users")
    suspend fun updateUser(
        @Header("Authorization") token: String,
        @Query("id") id: String,
        @Header("Prefer") prefer: String = "return=minimal",
        @Body updates: Map<String, Any?>
    ): Response<List<Map<String, Any?>>>

    @PUT
    suspend fun uploadStorageObject(
        @Url url: String,
        @Header("Authorization") token: String,
        @Header("x-upsert") upsert: String = "true",
        @Header("Content-Type") contentType: String,
        @Body body: RequestBody
    ): Response<Unit>

    @GET("rest/v1/app_version")
    suspend fun listAppVersions(
        @Header("Authorization") token: String,
        @Query("select") select: String = "id,version,build_number,download_url,description,force_update,min_build_number,created_at",
        // Prefer build_number ordering to avoid relying on clock/created_at correctness.
        @Query("order") order: String = "build_number.desc,created_at.desc",
        @Query("limit") limit: Int = 1
    ): Response<List<AppVersionRow>>
}

data class AppVersionRow(
    val id: String,
    val version: String,
    val build_number: Int,
    val download_url: String?,
    val description: String?,
    val force_update: Boolean?,
    val min_build_number: Int?,
    val created_at: String?
)
