-- Supabase music bootstrap optimization
-- Run this in Supabase SQL Editor.
-- Purpose:
-- 1. Add covering indexes for startup queries.
-- 2. Expose a single RPC to fetch favorites/history/playlists in one request.

create index if not exists idx_liked_songs_user_created_at
    on public.liked_songs(user_id, created_at desc);

create index if not exists idx_music_history_user_played_at
    on public.music_history(user_id, played_at desc);

create index if not exists idx_music_playlists_user_updated_at
    on public.music_playlists(user_id, updated_at desc, created_at desc);

create or replace function public.get_music_library_bootstrap(
    p_favorites_limit integer default 200,
    p_history_limit integer default 100,
    p_playlists_limit integer default 100
)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
    select jsonb_build_object(
        'favorites',
        coalesce((
            select jsonb_agg(row_to_json(fav))
            from (
                select
                    song_id,
                    source,
                    name,
                    artist,
                    album,
                    cover_url,
                    duration,
                    created_at
                from public.liked_songs
                where user_id = auth.uid()
                order by created_at desc
                limit greatest(p_favorites_limit, 1)
            ) fav
        ), '[]'::jsonb),
        'history',
        coalesce((
            select jsonb_agg(row_to_json(hist))
            from (
                select
                    song_id,
                    source,
                    name,
                    artist,
                    album,
                    cover_url,
                    duration,
                    played_at
                from public.music_history
                where user_id = auth.uid()
                order by played_at desc
                limit greatest(p_history_limit, 1)
            ) hist
        ), '[]'::jsonb),
        'playlists',
        coalesce((
            select jsonb_agg(row_to_json(pl))
            from (
                select
                    id,
                    name,
                    description,
                    cover_url,
                    is_public,
                    created_at,
                    updated_at
                from public.music_playlists
                where user_id = auth.uid()
                order by updated_at desc nulls last, created_at desc
                limit greatest(p_playlists_limit, 1)
            ) pl
        ), '[]'::jsonb)
    );
$$;

grant execute on function public.get_music_library_bootstrap(integer, integer, integer) to authenticated;
