-- Ministry AI 360 waitlist: run in a Supabase project once it exists.
-- Registration goes through an Edge Function using the service role (server-side only).
-- The browser never receives the service-role key; it calls the function endpoint only.
create extension if not exists citext;

create table churches (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 200),
  country char(2) not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  public_listing boolean not null default false,
  created_at timestamptz not null default now(),
  unique (lower(name), country)
);
create table waitlist_members (
  id uuid primary key default gen_random_uuid(),
  reference text not null unique,
  full_name text not null check (char_length(full_name) between 2 and 200),
  email citext not null unique,               -- duplicate-email handling
  church_id uuid references churches(id),
  role text not null,
  country char(2) not null,
  interests text[] not null default '{}',
  privacy_accepted_at timestamptz not null,
  created_at timestamptz not null default now()
);
create table church_invites (
  id uuid primary key default gen_random_uuid(),
  church_id uuid not null references churches(id),
  token text not null unique,
  created_at timestamptz not null default now()
);
create table registration_events (
  id bigint generated always as identity primary key,
  member_id uuid references waitlist_members(id),
  event text not null,
  created_at timestamptz not null default now()
);
create table waitlist_admins (user_id uuid primary key references auth.users(id));

alter table churches enable row level security;
alter table waitlist_members enable row level security;
alter table church_invites enable row level security;
alter table registration_events enable row level security;
alter table waitlist_admins enable row level security;

-- Public: approved, publicly listed churches only. No member rows are ever readable.
create policy "public reads approved churches" on churches for select
  using (status = 'approved' and public_listing);
-- Admins: full access via waitlist_admins membership.
create policy "admins manage churches" on churches for all
  using (exists (select 1 from waitlist_admins a where a.user_id = auth.uid()));
create policy "admins read members" on waitlist_members for select
  using (exists (select 1 from waitlist_admins a where a.user_id = auth.uid()));
create policy "admins read invites" on church_invites for select
  using (exists (select 1 from waitlist_admins a where a.user_id = auth.uid()));
create policy "admins read events" on registration_events for select
  using (exists (select 1 from waitlist_admins a where a.user_id = auth.uid()));

-- Public aggregate counts without exposing members.
create view church_public_counts as
  select c.id, c.name, c.country, count(m.id) as registrations
  from churches c left join waitlist_members m on m.church_id = c.id
  where c.status = 'approved' and c.public_listing group by c.id;
