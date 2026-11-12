#!/usr/bin/env bash
# Race test for the friend limit. A free user with one place left receives several requests,
# and all of them are accepted at the same moment from separate connections. Exactly one may succeed.
# Run after test.sql:  ./test-concurrency.sh summa_test
set -euo pipefail
db="${1:-summa_test}"
psql -q -v ON_ERROR_STOP=1 -d "$db" <<'SQL'
delete from auth.users where id::text like '30000000-%';
insert into auth.users select ('30000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid from generate_series(0, 9) g;
insert into public.profiles (id, username) select id, 'race_' || right(id::text, 2) from auth.users where id::text like '30000000-%';
-- User 00 already has one friend (01) and eight pending requests (02..09).
insert into public.friendships (requester, addressee, status) values ('30000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000000', 'accepted');
insert into public.friendships (requester, addressee)
  select ('30000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid, '30000000-0000-0000-0000-000000000000' from generate_series(2, 9) g;
SQL
for round in 1 2 3; do
  for g in 2 3 4 5 6 7 8 9; do
    psql -q -d "$db" -c "set role authenticated; select set_config('request.jwt.claim.sub', '30000000-0000-0000-0000-000000000000', false); select public.respond_friend('30000000-0000-0000-0000-00000000000$g', true);" >/dev/null 2>&1 &
  done
  wait
done
count=$(psql -At -d "$db" -c "select public.friend_count('30000000-0000-0000-0000-000000000000')")
pending=$(psql -At -d "$db" -c "select count(*) from public.friendships where addressee = '30000000-0000-0000-0000-000000000000' and status = 'pending'")
echo "accepted friends after 24 simultaneous acceptances: $count (limit 2), still pending: $pending"
[ "$count" = "2" ] && [ "$pending" = "7" ] && echo "CONCURRENCY CHECK PASSED" || { echo "CONCURRENCY CHECK FAILED"; exit 1; }
