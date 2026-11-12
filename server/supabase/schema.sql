-- Summa social backend (Supabase: Auth + PostgreSQL).
-- Apply once to a Supabase project (SQL editor or `psql`). Safe to re-run.
--
-- Principles
--   * Habit tracking stays local-first on the phone. Only what a person chooses to share is stored here.
--   * Every table has row level security. Other people's rows are reachable only through the
--     functions below, which check friendship, privacy settings, blocks, and Summa Pro on the server.
--   * Summa Pro comes from `entitlements`, which no client can write. It is filled by the
--     `sync-entitlement` edge function after it verifies an App Store transaction.
--   * Onboarding answers and progress photos are never uploaded.

create extension if not exists citext;

-- ---------------------------------------------------------------- tables

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username citext not null unique check (username ~ '^[a-z][a-z0-9_]{2,19}$' and username !~ '__' and username !~ '_$'),
  plan_start date,
  chapter int not null default 1,
  share_heatmap boolean not null default true,
  share_activity boolean not null default true,
  nudges_muted boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.entitlements (
  user_id uuid primary key references auth.users (id) on delete cascade,
  is_pro boolean not null default false,
  product_id text,
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);

do $$ begin
  create type public.friend_status as enum ('pending', 'accepted', 'blocked');
exception when duplicate_object then null; end $$;

-- One row per pair. `requester` sent the request, or is the person who blocked.
create table if not exists public.friendships (
  requester uuid not null references auth.users (id) on delete cascade,
  addressee uuid not null references auth.users (id) on delete cascade,
  status public.friend_status not null default 'pending',
  created_at timestamptz not null default now(),
  primary key (requester, addressee),
  check (requester <> addressee)
);
create unique index if not exists friendships_pair on public.friendships (least(requester, addressee), greatest(requester, addressee));

create table if not exists public.shared_habits (
  user_id uuid not null references auth.users (id) on delete cascade,
  habit_id uuid not null,
  title text not null check (char_length(title) between 1 and 60),
  color_hex text not null check (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  hidden boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, habit_id)
);

-- One row per habit per scheduled day. The primary key makes a duplicate check-in impossible,
-- so repeating a sync or a tap can never inflate a score.
create table if not exists public.shared_days (
  user_id uuid not null references auth.users (id) on delete cascade,
  habit_id uuid not null,
  day date not null check (day <= current_date + 1),
  done boolean not null,
  primary key (user_id, habit_id, day),
  foreign key (user_id, habit_id) references public.shared_habits (user_id, habit_id) on delete cascade
);
create index if not exists shared_days_user_day on public.shared_days (user_id, day);

create table if not exists public.nudges (
  id bigint generated always as identity primary key,
  sender uuid not null references auth.users (id) on delete cascade,
  recipient uuid not null references auth.users (id) on delete cascade,
  message_key text not null check (message_key in ('keep_going', 'one_small_step', 'thinking_of_you', 'proud_of_you')),
  day date not null default current_date,
  created_at timestamptz not null default now(),
  unique (sender, recipient, day)            -- at most one nudge per friend per day
);

create table if not exists public.activity (
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('week_complete', 'entered_momentum', 'entered_transformation', 'day_90', 'graduated')),
  detail int not null default 0,
  chapter int not null default 1,
  created_at timestamptz not null default now(),
  primary key (user_id, kind, detail, chapter)
);

-- ---------------------------------------------------------------- helpers

create or replace function public.is_pro(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_pro and (expires_at is null or expires_at > now()) from public.entitlements where user_id = uid), false);
$$;

create or replace function public.are_friends(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.friendships
                 where status = 'accepted' and ((requester = a and addressee = b) or (requester = b and addressee = a)));
$$;

create or replace function public.is_blocked(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.friendships
                 where status = 'blocked' and ((requester = a and addressee = b) or (requester = b and addressee = a)));
$$;

create or replace function public.require_pro() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  if not public.is_pro(me) then raise exception 'pro_required' using errcode = '42501'; end if;
  return me;
end $$;

-- ---------------------------------------------------------------- row level security
-- Clients may read and write only their own rows directly. Everything about other people goes through functions.

alter table public.profiles enable row level security;
alter table public.entitlements enable row level security;
alter table public.friendships enable row level security;
alter table public.shared_habits enable row level security;
alter table public.shared_days enable row level security;
alter table public.nudges enable row level security;
alter table public.activity enable row level security;

drop policy if exists profiles_own on public.profiles;
create policy profiles_own on public.profiles for all using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists entitlements_read_own on public.entitlements;
create policy entitlements_read_own on public.entitlements for select using (user_id = auth.uid());
-- No insert/update/delete policy: only the service role (edge function) can write entitlements.

drop policy if exists friendships_read_own on public.friendships;
create policy friendships_read_own on public.friendships for select using (auth.uid() in (requester, addressee));

drop policy if exists shared_habits_own on public.shared_habits;
create policy shared_habits_own on public.shared_habits for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists shared_days_own on public.shared_days;
create policy shared_days_own on public.shared_days for all using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists nudges_read_own on public.nudges;
create policy nudges_read_own on public.nudges for select using (auth.uid() in (sender, recipient));

drop policy if exists activity_own on public.activity;
create policy activity_own on public.activity for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------- functions the app calls

-- Creates or updates the caller's profile. A taken username fails with a unique violation (23505).
create or replace function public.set_profile(p_username text, p_plan_start date, p_chapter int) returns public.profiles
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); result public.profiles;
begin
  if me is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  insert into public.profiles (id, username, plan_start, chapter) values (me, lower(p_username), p_plan_start, coalesce(p_chapter, 1))
  on conflict (id) do update set username = excluded.username, plan_start = excluded.plan_start, chapter = excluded.chapter
  returning * into result;
  return result;
end $$;

create or replace function public.set_privacy(p_share_heatmap boolean, p_share_activity boolean, p_nudges_muted boolean) returns void
language sql security definer set search_path = public as $$
  update public.profiles set share_heatmap = p_share_heatmap, share_activity = p_share_activity, nudges_muted = p_nudges_muted where id = auth.uid();
$$;

-- Username search. Returns usernames only, never progress, and never people who have a block with the caller.
create or replace function public.search_users(q text) returns table (user_id uuid, username text)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.require_pro();
begin
  return query
    select p.id, p.username::text from public.profiles p
    where p.id <> me and char_length(q) >= 3 and p.username like lower(replace(replace(q, '%', ''), '_', '\_')) || '%'
      and not public.is_blocked(me, p.id)
    order by p.username limit 20;
end $$;

create or replace function public.request_friend(target uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := public.require_pro();
begin
  if target = me or public.is_blocked(me, target) then return; end if;
  -- If they already asked me, this accepts it.
  update public.friendships set status = 'accepted' where requester = target and addressee = me and status = 'pending';
  if found then return; end if;
  insert into public.friendships (requester, addressee) values (me, target) on conflict do nothing;
end $$;

create or replace function public.respond_friend(from_user uuid, accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := public.require_pro();
begin
  if accept then
    update public.friendships set status = 'accepted' where requester = from_user and addressee = me and status = 'pending';
  else
    delete from public.friendships where requester = from_user and addressee = me and status = 'pending';
  end if;
end $$;

-- Removing does not need Pro, so someone whose subscription lapsed can still leave.
create or replace function public.remove_friend(other uuid) returns void
language sql security definer set search_path = public as $$
  delete from public.friendships
  where status <> 'blocked' and ((requester = auth.uid() and addressee = other) or (requester = other and addressee = auth.uid()));
$$;

create or replace function public.block_user(other uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null or other = me then return; end if;
  delete from public.friendships where (requester = me and addressee = other) or (requester = other and addressee = me and status <> 'blocked');
  insert into public.friendships (requester, addressee, status) values (me, other, 'blocked') on conflict do nothing;
end $$;

create or replace function public.unblock_user(other uuid) returns void
language sql security definer set search_path = public as $$
  delete from public.friendships where requester = auth.uid() and addressee = other and status = 'blocked';
$$;

-- Friends, incoming requests, outgoing requests, and people the caller blocked.
create or replace function public.friends_overview() returns table (user_id uuid, username text, relation text)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.require_pro();
begin
  return query
    select p.id, p.username::text,
           case when f.status = 'accepted' then 'friend'
                when f.status = 'blocked' then 'blocked'
                when f.requester = me then 'outgoing' else 'incoming' end
    from public.friendships f
    join public.profiles p on p.id = case when f.requester = me then f.addressee else f.requester end
    where me in (f.requester, f.addressee) and (f.status <> 'blocked' or f.requester = me)
    order by 3, 2;
end $$;

-- The caller plus accepted friends who share their heatmap. `week_start` is the Monday of the current week.
create or replace function public.leaderboard(week_start date)
returns table (user_id uuid, username text, plan_start date, week_completed int, week_scheduled int, total_completed int, total_scheduled int, is_me boolean)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.require_pro();
begin
  return query
    select p.id, p.username::text, p.plan_start,
           coalesce(count(*) filter (where d.done and d.day between week_start and week_start + 6), 0)::int,
           coalesce(count(*) filter (where d.day between week_start and least(week_start + 6, current_date)), 0)::int,
           coalesce(count(*) filter (where d.done), 0)::int,
           coalesce(count(d.day), 0)::int,
           p.id = me
    from public.profiles p
    left join public.shared_days d on d.user_id = p.id and d.day >= coalesce(p.plan_start, d.day)
    where p.id = me or (public.are_friends(me, p.id) and p.share_heatmap)
    group by p.id;
end $$;

-- A friend's shared 90 days. Empty unless the two are accepted friends and the friend shares their heatmap.
-- Hidden habits are never returned.
create or replace function public.friend_heatmap(friend uuid)
returns table (habit_id uuid, title text, color_hex text, day date, done boolean)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.require_pro();
begin
  if not public.are_friends(me, friend) then return; end if;
  if not exists (select 1 from public.profiles where id = friend and share_heatmap) then return; end if;
  return query
    select h.habit_id, h.title, h.color_hex, d.day, d.done
    from public.shared_habits h
    join public.profiles p on p.id = h.user_id
    join public.shared_days d on d.user_id = h.user_id and d.habit_id = h.habit_id and d.day >= coalesce(p.plan_start, d.day)
    where h.user_id = friend and not h.hidden
    order by h.title, d.day;
end $$;

-- One supportive nudge per friend per day, from a fixed list. Fails quietly if muted; the unique key enforces the limit.
create or replace function public.send_nudge(target uuid, p_message_key text) returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := public.require_pro();
begin
  if p_message_key not in ('keep_going', 'one_small_step', 'thinking_of_you', 'proud_of_you') then
    raise exception 'unknown_message' using errcode = '22023';
  end if;
  if not public.are_friends(me, target) then return false; end if;
  if exists (select 1 from public.profiles where id = target and nudges_muted) then return false; end if;
  insert into public.nudges (sender, recipient, message_key) values (me, target, p_message_key) on conflict do nothing;
  return found;
end $$;

create or replace function public.my_nudges() returns table (from_username text, message_key text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.username::text, n.message_key, n.created_at
  from public.nudges n join public.profiles p on p.id = n.sender
  where n.recipient = auth.uid() and n.created_at > now() - interval '7 days'
    and not public.is_blocked(n.sender, n.recipient)
    and not exists (select 1 from public.profiles me where me.id = auth.uid() and me.nudges_muted)
  order by n.created_at desc limit 30;
$$;

create or replace function public.activity_feed() returns table (username text, kind text, detail int, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := public.require_pro();
begin
  return query
    select p.username::text, a.kind, a.detail, a.created_at
    from public.activity a join public.profiles p on p.id = a.user_id
    where a.user_id = me or (public.are_friends(me, a.user_id) and p.share_activity)
    order by a.created_at desc limit 50;
end $$;

-- Deletes the caller's account and, by cascade, everything they stored here.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not_signed_in' using errcode = '28000'; end if;
  delete from auth.users where id = me;
end $$;

revoke all on function public.is_pro(uuid), public.are_friends(uuid, uuid), public.is_blocked(uuid, uuid), public.require_pro() from public, anon;
grant execute on function public.is_pro(uuid), public.are_friends(uuid, uuid), public.is_blocked(uuid, uuid), public.require_pro() to authenticated;
revoke all on function public.set_profile(text, date, int), public.set_privacy(boolean, boolean, boolean), public.search_users(text),
  public.request_friend(uuid), public.respond_friend(uuid, boolean), public.remove_friend(uuid), public.block_user(uuid),
  public.unblock_user(uuid), public.friends_overview(), public.leaderboard(date), public.friend_heatmap(uuid),
  public.send_nudge(uuid, text), public.my_nudges(), public.activity_feed(), public.delete_my_account() from public, anon;
grant execute on function public.set_profile(text, date, int), public.set_privacy(boolean, boolean, boolean), public.search_users(text),
  public.request_friend(uuid), public.respond_friend(uuid, boolean), public.remove_friend(uuid), public.block_user(uuid),
  public.unblock_user(uuid), public.friends_overview(), public.leaderboard(date), public.friend_heatmap(uuid),
  public.send_nudge(uuid, text), public.my_nudges(), public.activity_feed(), public.delete_my_account() to authenticated;
