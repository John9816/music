package com.music.player.data.live

import androidx.room.*
import android.content.Context

@Entity(tableName = "tv_channels")
data class TvChannelEntity(
    @PrimaryKey val id: String,
    val name: String,
    val group: String,
    val playUrl: String,
    val logoUrl: String = "",
    val savedAt: Long = System.currentTimeMillis()
)

@Dao
interface TvChannelDao {
    @Query("SELECT * FROM tv_channels ORDER BY savedAt DESC LIMIT 1")
    suspend fun getLatest(): TvChannelEntity?

    @Query("SELECT * FROM tv_channels ORDER BY group, name")
    suspend fun getAll(): List<TvChannelEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(channels: List<TvChannelEntity>)

    @Query("DELETE FROM tv_channels")
    suspend fun clear()
}

@Database(entities = [TvChannelEntity::class], version = 1, exportSchema = false)
abstract class TvChannelDatabase : RoomDatabase() {
    abstract fun tvChannelDao(): TvChannelDao

    companion object {
        @Volatile
        private var INSTANCE: TvChannelDatabase? = null

        fun getDatabase(context: Context): TvChannelDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    TvChannelDatabase::class.java,
                    "tv_channels.db"
                ).build()
                INSTANCE = instance
                instance
            }
        }
    }
}
