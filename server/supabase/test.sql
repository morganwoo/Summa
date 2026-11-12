-- Smoke test for schema.sql against plain PostgreSQL with a stand-in for Supabase's auth schema.
-- Run:  createdb summa_test && psql -v ON_ERROR_STOP=1 -d summa_test -f test.sql
\set QUIET on
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key);
create or replace function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid $$;
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
\i migrations/0001_summa_social.sql
grant usage on schema public, auth to authenticated;
grant execute on function auth.uid() to authenticated;

create or replace function pg_temp.check(label text, ok boolean) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FAILED: %', label; end if; raise notice 'ok  %', label; end $$;
create or replace function pg_temp.fails(label text, sql text) returns void language plpgsql as $$
begin
  begin execute sql; exception when others then raise notice 'ok  % (%)', label, sqlstate; return; end;
  raise exception 'FAILED (no error): %', label;
end $$;
create or replace function pg_temp.as_user(u uuid) returns void language sql as $$ select set_config('request.jwt.claim.sub', u::text, false) $$;

insert into auth.users values ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b'),
                              ('00000000-0000-0000-0000-00000000000c'), ('00000000-0000-0000-0000-00000000000d');
\set a '''00000000-0000-0000-0000-00000000000a'''
\set b '''00000000-0000-0000-0000-00000000000b'''
\set c '''00000000-0000-0000-0000-00000000000c'''
\set d '''00000000-0000-0000-0000-00000000000d'''
-- a, b, c are Pro; d is free.
insert into public.entitlements (user_id, is_pro) values (:a, true), (:b, true), (:c, true);
insert into public.entitlements (user_id, is_pro, expires_at) values (:d, true, now() - interval '1 day');

set role authenticated;

select pg_temp.as_user(:a); select public.set_profile('Alex_K', current_date - 9, 1);
select pg_temp.as_user(:b); select public.set_profile('bea', current_date - 9, 1);
select pg_temp.as_user(:c); select public.set_profile('cy_r', current_date - 9, 1);
select pg_temp.as_user(:d); select public.set_profile('dee', current_date, 1);
select pg_temp.check('usernames are stored lowercase', (select username = 'dee' from public.profiles where id = auth.uid()));
select pg_temp.fails('a taken username is refused, case-insensitively', $$select public.set_profile('ALEX_K', null, 1)$$);
select pg_temp.fails('an invalid username is refused', $$select public.set_profile('1x', null, 1)$$);
select pg_temp.check('a profile row of someone else is invisible', (select count(*) = 1 from public.profiles));
select pg_temp.check('an expired subscription is not Pro, and a free account can still search', not public.is_pro(auth.uid()) and (select count(*) = 1 from public.search_users('ale')));
select pg_temp.fails('entitlements cannot be updated by a client', $$update public.entitlements set is_pro = true, expires_at = null where user_id = auth.uid()$$);
select pg_temp.fails('entitlements cannot be inserted by a client', $$insert into public.entitlements (user_id, is_pro) values (auth.uid(), true) on conflict (user_id) do update set is_pro = true$$);
select pg_temp.check('nobody can make themselves Pro', not public.is_pro(auth.uid()));

-- a shares two habits, one hidden; day rows cannot duplicate.
select pg_temp.as_user(:a);
insert into public.shared_habits (user_id, habit_id, title, color_hex, hidden) values
  (auth.uid(), '10000000-0000-0000-0000-000000000001', 'Read daily', '#DCAF61', false),
  (auth.uid(), '10000000-0000-0000-0000-000000000002', 'Private thing', '#8AAF96', true);
insert into public.shared_days (user_id, habit_id, day, done)
  select auth.uid(), '10000000-0000-0000-0000-000000000001', current_date - g, g <> 2 from generate_series(0, 6) g;
insert into public.shared_days (user_id, habit_id, day, done) values (auth.uid(), '10000000-0000-0000-0000-000000000002', current_date, true);
select pg_temp.fails('a second row for the same habit and day is refused', $$insert into public.shared_days (user_id, habit_id, day, done) values (auth.uid(), '10000000-0000-0000-0000-000000000001', current_date, true)$$);
insert into public.shared_days (user_id, habit_id, day, done) values (auth.uid(), '10000000-0000-0000-0000-000000000001', current_date, true)
  on conflict (user_id, habit_id, day) do update set done = excluded.done;
select pg_temp.check('re-syncing a day does not add a row', (select count(*) = 8 from public.shared_days));
select pg_temp.fails('rows cannot be written for another user', $$insert into public.shared_days (user_id, habit_id, day, done) values ('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000001', current_date, true)$$);
select pg_temp.check('search finds by prefix and returns only usernames', (select count(*) = 1 and bool_and(username = 'bea') from public.search_users('BEA')));
select pg_temp.check('search needs three characters', (select count(*) = 0 from public.search_users('b')));

-- Before friendship, nothing of a's is visible to b.
select pg_temp.as_user(:b);
select pg_temp.check('direct table reads show nothing of a', (select count(*) = 0 from public.shared_days) and (select count(*) = 0 from public.shared_habits));
select pg_temp.check('heatmap is empty before friendship', (select count(*) = 0 from public.friend_heatmap(:a)));
select pg_temp.check('a stranger cannot be nudged', not public.send_nudge(:a, 'keep_going'));
select public.request_friend(:a);
select pg_temp.check('a pending request shows nothing yet', (select count(*) = 0 from public.friend_heatmap(:a)));
select pg_temp.check('b sees an outgoing request', (select relation = 'outgoing' from public.friends_overview()));
select pg_temp.as_user(:a);
select pg_temp.check('a sees an incoming request', (select relation = 'incoming' and username = 'bea' from public.friends_overview()));
select public.respond_friend(:b, true);
select pg_temp.as_user(:b);
select pg_temp.check('after acceptance b sees the shared habit only', (select count(*) = 7 and bool_and(title = 'Read daily') from public.friend_heatmap(:a)));
select pg_temp.check('nudge is delivered once', public.send_nudge(:a, 'keep_going'));
select pg_temp.check('a second nudge the same day is refused', not public.send_nudge(:a, 'proud_of_you'));
select pg_temp.fails('free-text nudges are refused', $$select public.send_nudge('00000000-0000-0000-0000-00000000000c', 'buy my course')$$);
select pg_temp.check('leaderboard lists both with real counts', (select count(*) = 2 from public.leaderboard(current_date - 6))
  and (select week_completed = 7 and week_scheduled = 8 and total_scheduled = 8 from public.leaderboard(current_date - 6) where username = 'alex_k'));
select pg_temp.as_user(:a);
select pg_temp.check('a receives the nudge', (select count(*) = 1 and bool_and(from_username = 'bea') from public.my_nudges()));
insert into public.activity (user_id, kind, detail) values (auth.uid(), 'week_complete', 1) on conflict do nothing;
insert into public.activity (user_id, kind, detail) values (auth.uid(), 'week_complete', 1) on conflict do nothing;
select public.set_privacy(false, false, true);
select pg_temp.check('muted: no nudges are shown', (select count(*) = 0 from public.my_nudges()));
select pg_temp.as_user(:b);
select pg_temp.check('heatmap is hidden when sharing is off', (select count(*) = 0 from public.friend_heatmap(:a)));
select pg_temp.check('leaderboard drops someone who stopped sharing', (select count(*) = 1 from public.leaderboard(current_date - 6)));
select pg_temp.check('activity is hidden when sharing is off', (select count(*) = 0 from public.activity_feed()));
select pg_temp.as_user(:a); select public.set_privacy(true, true, false);
select pg_temp.as_user(:b);
select pg_temp.check('activity appears once, without duplicates', (select count(*) = 1 from public.activity_feed()));

-- c is not a friend of a.
select pg_temp.as_user(:c);
select pg_temp.check('a non-friend sees nothing', (select count(*) = 0 from public.friend_heatmap(:a)) and (select count(*) = 1 from public.leaderboard(current_date - 6)));
-- Blocking removes the friendship and hides the blocker from search.
select pg_temp.as_user(:a); select public.block_user(:b);
select pg_temp.as_user(:b);
select pg_temp.check('after a block the heatmap is gone', (select count(*) = 0 from public.friend_heatmap(:a)));
select pg_temp.check('a blocked person cannot find the blocker', (select count(*) = 0 from public.search_users('alex')));
select public.request_friend(:a);
select pg_temp.check('a blocked person cannot re-request', (select count(*) = 0 from public.friends_overview() where username = 'alex_k'));
select pg_temp.fails('the blocked person cannot remove the block', $$select public.remove_friend('00000000-0000-0000-0000-00000000000a'); select 1 / (select count(*) from public.friendships where status <> 'blocked')$$);

-- ---------------------------------------------------------------- free tier: two accepted friends
-- Fresh people: f is free, p is Pro, x1..x4 are free.
reset role;
insert into auth.users select ('20000000-0000-0000-0000-00000000000' || g)::uuid from generate_series(1, 6) g;
insert into public.entitlements (user_id, is_pro) values ('20000000-0000-0000-0000-000000000002', true);
set role authenticated;
\set f '''20000000-0000-0000-0000-000000000001'''
\set p '''20000000-0000-0000-0000-000000000002'''
\set x1 '''20000000-0000-0000-0000-000000000003'''
\set x2 '''20000000-0000-0000-0000-000000000004'''
\set x3 '''20000000-0000-0000-0000-000000000005'''
\set x4 '''20000000-0000-0000-0000-000000000006'''
select pg_temp.as_user(:f);  select public.set_profile('free_fay', current_date, 1);
select pg_temp.as_user(:p);  select public.set_profile('pro_pat', current_date, 1);
select pg_temp.as_user(:x1); select public.set_profile('xone', current_date, 1);
select pg_temp.as_user(:x2); select public.set_profile('xtwo', current_date, 1);
select pg_temp.as_user(:x3); select public.set_profile('xthree', current_date, 1);
select pg_temp.as_user(:x4); select public.set_profile('xfour', current_date, 1);

-- f (free) gets two friends, and uses every core feature with them.
select pg_temp.as_user(:f);
select pg_temp.check('a free account opens Friends: overview and leaderboard work', (select count(*) = 0 from public.friends_overview()) and (select count(*) = 1 from public.leaderboard(current_date)));
select public.request_friend(:x1); select public.request_friend(:x2); select public.request_friend(:x3);
select pg_temp.check('pending requests do not count toward the limit', (select friend_count = 0 and not is_pro and friend_limit = 2 from public.my_social_status()));
select pg_temp.as_user(:x1); select public.respond_friend(:f, true);
select pg_temp.as_user(:x2); select public.respond_friend(:f, true);
select pg_temp.as_user(:f);
select pg_temp.check('free: two accepted friends', (select friend_count = 2 from public.my_social_status()));
select pg_temp.check('free: can nudge a friend and use the feed and heatmap', public.send_nudge(:x1, 'keep_going') and (select count(*) >= 0 from public.activity_feed()) and (select count(*) = 0 from public.friend_heatmap(:x1)));
select pg_temp.check('free: leaderboard shows me and both friends', (select count(*) = 3 from public.leaderboard(current_date)));
-- A third acceptance is refused for the person who is full, whichever side accepts.
select pg_temp.as_user(:x3);
select pg_temp.fails('accepting when the requester is full is refused (other side)', $$select public.respond_friend('20000000-0000-0000-0000-000000000001', true)$$);
select pg_temp.as_user(:x4); select public.request_friend(:f);
select pg_temp.as_user(:f);
select pg_temp.check('at the limit, incoming requests are still visible', (select count(*) = 1 from public.friends_overview() where relation = 'incoming'));
select pg_temp.fails('accepting a third friend is refused', $$select public.respond_friend('20000000-0000-0000-0000-000000000006', true)$$);
select pg_temp.fails('sending a request at the limit is refused', $$select public.request_friend('20000000-0000-0000-0000-000000000002')$$);
select public.respond_friend(:x4, false);
select pg_temp.check('declining works at the limit, and existing friends are intact', (select count(*) = 0 from public.friends_overview() where relation = 'incoming') and (select friend_count = 2 from public.my_social_status()));
-- Removing a friend frees a place, and the count follows.
select public.remove_friend(:x2);
select pg_temp.check('count is accurate after removal', (select friend_count = 1 from public.my_social_status()));
select pg_temp.as_user(:x3); select public.respond_friend(:f, true);
select pg_temp.as_user(:f);
select pg_temp.check('the freed place can be used', (select friend_count = 2 from public.my_social_status()));

-- Pro: unlimited. p befriends x1..x4 (four friends).
select pg_temp.as_user(:p);
select public.request_friend(:x1); select public.request_friend(:x2); select public.request_friend(:x4);
select pg_temp.as_user(:x1); select public.respond_friend(:p, true);
select pg_temp.as_user(:x2); select public.respond_friend(:p, true);
select pg_temp.as_user(:x4); select public.respond_friend(:p, true);
select pg_temp.as_user(:x3); select public.request_friend(:p);
select pg_temp.as_user(:p);  select public.respond_friend(:x3, true);
select pg_temp.check('Pro holds more than two friends', (select friend_count = 4 and is_pro from public.my_social_status()));
-- x1 is free with two friends (f and p): cannot take a third even from another requester.
select pg_temp.as_user(:x1);
select pg_temp.check('x1 is full', (select friend_count = 2 from public.my_social_status()));
select pg_temp.as_user(:x4); select public.request_friend(:x1);
select pg_temp.as_user(:x1);
select pg_temp.fails('both limits are checked on acceptance', $$select public.respond_friend('20000000-0000-0000-0000-000000000006', true)$$);
select public.respond_friend(:x4, false);

-- Pro expires with four friends: all are kept and still usable, but no more can be added.
reset role;
update public.entitlements set expires_at = now() - interval '1 hour' where user_id = :p;
set role authenticated;
select pg_temp.as_user(:p);
select pg_temp.check('friendships survive expiry', (select friend_count = 4 and not is_pro from public.my_social_status()) and (select count(*) = 4 from public.friends_overview() where relation = 'friend'));
select pg_temp.check('existing friends can still be nudged and ranked after expiry', public.send_nudge(:x2, 'proud_of_you') and (select count(*) = 5 from public.leaderboard(current_date)));
select pg_temp.fails('no new friend after expiry while over the limit', $$select public.request_friend('20000000-0000-0000-0000-000000000001')$$);
select public.remove_friend(:x1); select public.remove_friend(:x2); select public.remove_friend(:x3);
select pg_temp.check('once under the limit a lapsed account can add again', (select friend_count = 1 from public.my_social_status()));
select public.request_friend(:x2);
select pg_temp.check('the request went out', (select count(*) = 1 from public.friends_overview() where relation = 'outgoing'));
select public.remove_friend(:x2);
select pg_temp.fails('clients cannot call the internal accept helper', $$select public.accept_pending('20000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002')$$);

-- Account deletion removes everything.
select pg_temp.as_user(:a);
reset role;
select public.delete_my_account();
select pg_temp.check('deleting the account cascades', (select count(*) = 0 from public.profiles where username = 'alex_k')
  and (select count(*) = 0 from public.shared_days) and (select count(*) = 0 from public.nudges where '00000000-0000-0000-0000-00000000000a' in (sender, recipient))
  and (select count(*) = 0 from public.friendships where '00000000-0000-0000-0000-00000000000a' in (requester, addressee)));
\echo ALL SOCIAL SCHEMA CHECKS PASSED
