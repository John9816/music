-- 音乐播放器 Supabase 数据库表结构
-- 在 Supabase Dashboard -> SQL Editor 中执行此脚本
-- 注意：此脚本将在现有的 daohangv2 数据库中添加音乐相关的表

-- ==========================================
-- 音乐相关表（新增）
-- ==========================================

-- 1. 用户音乐收藏表
CREATE TABLE IF NOT EXISTS music_favorites (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    song_id BIGINT NOT NULL,
    song_name TEXT NOT NULL,
    artist_name TEXT NOT NULL,
    album_cover TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, song_id)
);

-- 为收藏表创建索引
CREATE INDEX IF NOT EXISTS idx_music_favorites_user_id ON music_favorites(user_id);
CREATE INDEX IF NOT EXISTS idx_music_favorites_created_at ON music_favorites(created_at DESC);

-- 启用行级安全策略 (RLS)
ALTER TABLE music_favorites ENABLE ROW LEVEL SECURITY;

-- 用户只能查看自己的收藏
CREATE POLICY "Users can view their own music favorites"
    ON music_favorites FOR SELECT
    USING (auth.uid() = user_id);

-- 用户只能添加自己的收藏
CREATE POLICY "Users can insert their own music favorites"
    ON music_favorites FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- 用户只能删除自己的收藏
CREATE POLICY "Users can delete their own music favorites"
    ON music_favorites FOR DELETE
    USING (auth.uid() = user_id);

-- 2. 音乐播放历史表
CREATE TABLE IF NOT EXISTS music_play_history (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    song_id BIGINT NOT NULL,
    song_name TEXT NOT NULL,
    artist_name TEXT NOT NULL,
    played_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 为播放历史表创建索引
CREATE INDEX IF NOT EXISTS idx_music_play_history_user_id ON music_play_history(user_id);
CREATE INDEX IF NOT EXISTS idx_music_play_history_played_at ON music_play_history(played_at DESC);

-- 启用行级安全策略 (RLS)
ALTER TABLE music_play_history ENABLE ROW LEVEL SECURITY;

-- 用户只能查看自己的播放历史
CREATE POLICY "Users can view their own music play history"
    ON music_play_history FOR SELECT
    USING (auth.uid() = user_id);

-- 用户只能添加自己的播放历史
CREATE POLICY "Users can insert their own music play history"
    ON music_play_history FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- 用户可以删除自己的播放历史
CREATE POLICY "Users can delete their own music play history"
    ON music_play_history FOR DELETE
    USING (auth.uid() = user_id);

-- 3. 用户音乐歌单表
CREATE TABLE IF NOT EXISTS music_playlists (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    cover_url TEXT,
    is_public BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 为歌单表创建索引
CREATE INDEX IF NOT EXISTS idx_music_playlists_user_id ON music_playlists(user_id);
CREATE INDEX IF NOT EXISTS idx_music_playlists_created_at ON music_playlists(created_at DESC);

-- 启用行级安全策略 (RLS)
ALTER TABLE music_playlists ENABLE ROW LEVEL SECURITY;

-- 用户可以查看自己的歌单和公开的歌单
CREATE POLICY "Users can view their own playlists and public playlists"
    ON music_playlists FOR SELECT
    USING (auth.uid() = user_id OR is_public = true);

-- 用户只能创建自己的歌单
CREATE POLICY "Users can insert their own playlists"
    ON music_playlists FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- 用户只能更新自己的歌单
CREATE POLICY "Users can update their own playlists"
    ON music_playlists FOR UPDATE
    USING (auth.uid() = user_id);

-- 用户只能删除自己的歌单
CREATE POLICY "Users can delete their own playlists"
    ON music_playlists FOR DELETE
    USING (auth.uid() = user_id);

-- 4. 歌单歌曲关联表
CREATE TABLE IF NOT EXISTS music_playlist_songs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    playlist_id UUID NOT NULL REFERENCES music_playlists(id) ON DELETE CASCADE,
    song_id BIGINT NOT NULL,
    song_name TEXT NOT NULL,
    artist_name TEXT NOT NULL,
    album_cover TEXT,
    sort_order INTEGER DEFAULT 0,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(playlist_id, song_id)
);

-- 为歌单歌曲表创建索引
CREATE INDEX IF NOT EXISTS idx_music_playlist_songs_playlist_id ON music_playlist_songs(playlist_id);
CREATE INDEX IF NOT EXISTS idx_music_playlist_songs_sort_order ON music_playlist_songs(sort_order);

-- 启用行级安全策略 (RLS)
ALTER TABLE music_playlist_songs ENABLE ROW LEVEL SECURITY;

-- 用户可以查看自己歌单的歌曲和公开歌单的歌曲
CREATE POLICY "Users can view songs in their playlists and public playlists"
    ON music_playlist_songs FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM music_playlists
            WHERE music_playlists.id = music_playlist_songs.playlist_id
            AND (music_playlists.user_id = auth.uid() OR music_playlists.is_public = true)
        )
    );

-- 用户只能向自己的歌单添加歌曲
CREATE POLICY "Users can insert songs into their own playlists"
    ON music_playlist_songs FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM music_playlists
            WHERE music_playlists.id = music_playlist_songs.playlist_id
            AND music_playlists.user_id = auth.uid()
        )
    );

-- 用户只能删除自己歌单中的歌曲
CREATE POLICY "Users can delete songs from their own playlists"
    ON music_playlist_songs FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM music_playlists
            WHERE music_playlists.id = music_playlist_songs.playlist_id
            AND music_playlists.user_id = auth.uid()
        )
    );

-- ==========================================
-- 创建视图：用户音乐统计信息
-- ==========================================
CREATE OR REPLACE VIEW music_user_stats AS
SELECT
    u.id as user_id,
    u.email,
    COUNT(DISTINCT mf.id) as favorite_count,
    COUNT(DISTINCT mph.id) as play_count,
    COUNT(DISTINCT mp.id) as playlist_count,
    MAX(mph.played_at) as last_played_at
FROM auth.users u
LEFT JOIN music_favorites mf ON u.id = mf.user_id
LEFT JOIN music_play_history mph ON u.id = mph.user_id
LEFT JOIN music_playlists mp ON u.id = mp.user_id
GROUP BY u.id, u.email;

-- ==========================================
-- 创建函数：自动更新歌单的 updated_at
-- ==========================================
CREATE OR REPLACE FUNCTION update_music_playlist_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 创建触发器
DROP TRIGGER IF EXISTS trigger_update_music_playlist_updated_at ON music_playlists;
CREATE TRIGGER trigger_update_music_playlist_updated_at
    BEFORE UPDATE ON music_playlists
    FOR EACH ROW
    EXECUTE FUNCTION update_music_playlist_updated_at();

-- ==========================================
-- 完成！
-- ==========================================
-- 现在音乐表已经添加到现有的 daohangv2 数据库中
-- 所有表都使用相同的 auth.users 表进行用户关联
-- 可以在 Android 应用中使用这些表了

