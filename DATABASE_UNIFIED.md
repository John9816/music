# 统一数据库配置说明

## 概述

音乐播放器项目和 daohangv2 项目共享同一个 Supabase 数据库实例。所有数据都存储在同一个数据库中，使用相同的用户认证系统。

## Supabase 配置

```
URL: https://vtvzpdupygvtytunrpdw.supabase.co
Anon Key: sb_publishable_DWdy6_bOXKnHO5aKG7cM0A__mo-PjT8
```

## 数据库表结构

### 共享表（来自 daohangv2）

#### 1. users (用户表)
```sql
- id: UUID (主键，关联 auth.users)
- email: TEXT
- username: TEXT
- nickname: TEXT
- signature: TEXT (个性签名)
- badge: TEXT (徽章)
- avatar_url: TEXT
- created_at: TIMESTAMP
```

#### 2. sparks (灵感/笔记)
```sql
- id: UUID
- user_id: UUID (外键 -> users)
- type: TEXT ('text' | 'image')
- content: TEXT
- created_at: TIMESTAMP
```

#### 3. guestbook_messages (留言板)
```sql
- id: UUID
- user_id: UUID
- content: TEXT
- nickname: TEXT
- avatar_url: TEXT
- created_at: TIMESTAMP
```

#### 4. categories (书签分类)
```sql
- id: UUID
- user_id: UUID
- title: TEXT
- icon_name: TEXT
- sort_order: INTEGER
```

#### 5. links (书签链接)
```sql
- id: UUID
- user_id: UUID
- category_id: UUID (外键 -> categories)
- title: TEXT
- url: TEXT
- description: TEXT
- icon_name: TEXT
- sort_order: INTEGER
```

### 音乐相关表（新增）

#### 6. music_favorites (音乐收藏)
```sql
- id: UUID (主键)
- user_id: UUID (外键 -> auth.users)
- song_id: BIGINT
- song_name: TEXT
- artist_name: TEXT
- album_cover: TEXT
- created_at: TIMESTAMP
- UNIQUE(user_id, song_id)
```

#### 7. music_play_history (播放历史)
```sql
- id: UUID (主键)
- user_id: UUID (外键 -> auth.users)
- song_id: BIGINT
- song_name: TEXT
- artist_name: TEXT
- played_at: TIMESTAMP
```

#### 8. music_playlists (用户歌单)
```sql
- id: UUID (主键)
- user_id: UUID (外键 -> auth.users)
- name: TEXT
- description: TEXT
- cover_url: TEXT
- is_public: BOOLEAN
- created_at: TIMESTAMP
- updated_at: TIMESTAMP
```

#### 9. music_playlist_songs (歌单歌曲)
```sql
- id: UUID (主键)
- playlist_id: UUID (外键 -> music_playlists)
- song_id: BIGINT
- song_name: TEXT
- artist_name: TEXT
- album_cover: TEXT
- sort_order: INTEGER
- added_at: TIMESTAMP
- UNIQUE(playlist_id, song_id)
```

## 数据关系

```
auth.users (Supabase 认证)
    ├── users (用户资料)
    ├── sparks (灵感笔记)
    ├── guestbook_messages (留言)
    ├── categories (书签分类)
    │   └── links (书签链接)
    ├── music_favorites (音乐收藏)
    ├── music_play_history (播放历史)
    └── music_playlists (歌单)
        └── music_playlist_songs (歌单歌曲)
```

## 安全策略 (RLS)

所有表都启用了行级安全策略（Row Level Security）：

1. **用户只能访问自己的数据**
   - 收藏、播放历史、歌单等都有用户隔离

2. **公开数据访问**
   - 公开歌单（is_public = true）可以被所有人查看
   - 用户资料可以被所有人查看

3. **级联删除**
   - 删除用户时，自动删除其所有相关数据

## 使用说明

### Android 项目

1. **认证**
   - 使用 `AuthRepository` 进行登录/注册
   - 自动在 `users` 表创建用户资料

2. **音乐功能**
   - 使用 `SupabaseRepository` 管理收藏、历史、歌单
   - 所有操作自动关联当前登录用户

3. **用户资料**
   - 从 `users` 表读取完整的用户信息
   - 支持更新 username, nickname, signature, avatar_url

### Web 项目 (daohangv2)

1. **认证**
   - 使用 `AuthContext` 管理用户状态
   - 共享相同的 Supabase Auth

2. **书签功能**
   - 使用 `bookmarkService` 管理分类和链接

3. **其他功能**
   - Sparks（灵感）
   - Guestbook（留言板）
   - Chat（聊天）

## 数据迁移

如果需要在 Supabase 中创建音乐相关的表，执行以下步骤：

1. 登录 Supabase Dashboard
2. 进入 SQL Editor
3. 执行 `supabase_schema.sql` 脚本
4. 验证表创建成功

## 注意事项

1. **表名前缀**
   - 音乐相关表使用 `music_` 前缀，避免命名冲突

2. **用户关联**
   - 所有表都通过 `user_id` 关联到 `auth.users`
   - 确保用户登录后才能访问数据

3. **数据一致性**
   - 使用事务确保数据一致性
   - 外键约束保证引用完整性

4. **性能优化**
   - 所有常用查询字段都有索引
   - 使用 `created_at DESC` 排序获取最新数据

## 测试

### 测试用户
```
邮箱: test@example.com
密码: 123456
```

### 测试步骤
1. 在 Android 应用中登录
2. 添加收藏歌曲
3. 查看播放历史
4. 在 Supabase Dashboard 验证数据
5. 在 daohangv2 Web 应用中使用相同账号登录
6. 验证用户资料一致

## 备份与恢复

Supabase 自动备份数据，可以在 Dashboard 中：
1. 查看备份历史
2. 恢复到指定时间点
3. 导出数据为 SQL 或 CSV

## 监控

在 Supabase Dashboard 可以监控：
1. API 请求数量
2. 数据库连接数
3. 存储使用量
4. 认证用户数

---

**最后更新**: 2026-03-08
**数据库版本**: 1.0
**状态**: 生产就绪
