do $$ begin create role anon; exception when duplicate_object then null; end $$; do $$ begin create role authenticated; exception when duplicate_object then null; end $$; do $$ begin create role service_role; exception when duplicate_object then null; end $$;
create schema auth; create table auth.users(id uuid primary key default gen_random_uuid());
create function auth.uid() returns uuid language sql as $$ select null::uuid $$;
