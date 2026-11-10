-- ERROR-404: run this complete script in Supabase SQL Editor.
-- Organizer accounts are created in Supabase Dashboard > Authentication > Users.
create extension if not exists pgcrypto;

do $$ begin
  create type public.event_status as enum ('draft','live','paused','ended');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.competitor_kind as enum ('individual','team');
exception when duplicate_object then null; end $$;

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(), name text not null,
  pin text not null unique check (pin ~ '^[0-9]{4,8}$'),
  status public.event_status not null default 'draft',
  current_question integer not null default 0 check (current_question between 0 and 10),
  question_seconds integer not null default 300 check (question_seconds between 30 and 3600),
  created_by uuid not null references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists public.competitors (
  id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events(id) on delete cascade,
  display_name text not null, kind public.competitor_kind not null, auth_user_id uuid references auth.users(id),
  score integer not null default 0 check (score >= 0), solved_count integer not null default 0 check (solved_count between 0 and 10),
  created_at timestamptz not null default now(), unique(event_id, display_name)
);
create table if not exists public.team_members (
  team_id uuid not null references public.competitors(id) on delete cascade,
  member_name text not null, primary key(team_id, member_name)
);
create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events(id) on delete cascade,
  question_number integer not null check (question_number between 0 and 10), title text not null,
  language text not null check (language in ('JavaScript','Python')), difficulty text not null,
  prompt text not null, starter_code text not null, points integer not null default 100,
  evaluator_config jsonb not null default '{}'::jsonb, unique(event_id, question_number)
);
create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(), event_id uuid not null references public.events(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  competitor_id uuid not null references public.competitors(id) on delete cascade,
  source_code text not null, submitted_at timestamptz not null default now(),
  verdict text not null default 'pending' check (verdict in ('pending','accepted','rejected','error')),
  awarded_points integer not null default 0 check (awarded_points >= 0), execution_ms integer,
  unique(question_id, competitor_id)
);
create index if not exists competitors_event_score_idx on public.competitors(event_id, score desc);
create index if not exists submissions_event_question_idx on public.submissions(event_id, question_id);

alter table public.events enable row level security;
alter table public.competitors enable row level security;
alter table public.team_members enable row level security;
alter table public.questions enable row level security;
alter table public.submissions enable row level security;

-- Remove broad legacy policies if this script is being applied over the starter schema.
drop policy if exists "event metadata readable" on public.events;
drop policy if exists "competitors visible for event leaderboard" on public.competitors;
drop policy if exists "team members readable" on public.team_members;
drop policy if exists "published question metadata readable" on public.questions;
drop policy if exists "organizer owns events" on public.events;
drop policy if exists "leaderboard visible" on public.competitors;
drop policy if exists "team members visible" on public.team_members;
create policy "organizer owns events" on public.events for all to authenticated using (created_by = auth.uid()) with check (created_by = auth.uid());
create policy "leaderboard visible" on public.competitors for select to anon, authenticated using (exists(select 1 from public.events e where e.id=event_id and e.status in ('live','paused','ended')));
create policy "team members visible" on public.team_members for select to anon, authenticated using (exists(select 1 from public.competitors c join public.events e on e.id=c.event_id where c.id=team_id and e.status in ('live','paused','ended')));
-- No direct browser writes to scores, questions, or submissions.
revoke all on public.questions from anon, authenticated;
revoke all on public.submissions from anon, authenticated;
grant select on public.events, public.competitors, public.team_members to anon, authenticated;

-- Only safe question fields are exposed to participants.
create or replace view public.public_questions as
 select q.id,q.event_id,q.question_number,q.title,q.language,q.difficulty,q.prompt,q.starter_code,q.points
 from public.questions q join public.events e on e.id=q.event_id
 where e.status='live' and q.question_number=e.current_question;
grant select on public.public_questions to anon, authenticated;

create or replace function public.create_event(p_name text,p_pin text,p_question_seconds integer default 300)
returns setof public.events language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Organizer sign-in required'; end if;
 if length(trim(p_name))=0 or p_pin !~ '^[0-9]{4,8}$' then raise exception 'Enter an event name and a 4-8 digit PIN'; end if;
 return query insert into public.events(name,pin,question_seconds,created_by)
 values(trim(p_name),p_pin,greatest(30,least(p_question_seconds,3600)),auth.uid()) returning *;
end; $$;

create or replace function public.get_live_event_by_pin(p_pin text)
returns table(id uuid,name text,pin text,status public.event_status,current_question integer,question_seconds integer)
language sql security definer set search_path=public as $$
 select e.id,e.name,e.pin,e.status,e.current_question,e.question_seconds from public.events e
 where e.pin=p_pin and e.status in ('live','paused') limit 1;
$$;

create or replace function public.join_event(p_pin text,p_display_name text,p_kind public.competitor_kind,p_members text[] default '{}')
returns uuid language plpgsql security definer set search_path=public as $$
declare v_event public.events; v_id uuid; v_member text;
begin
 select * into v_event from public.events where pin=p_pin and status='live' limit 1;
 if not found then raise exception 'Event PIN is invalid or the event is not live'; end if;
 if length(trim(p_display_name))=0 then raise exception 'Enter a participant or team name'; end if;
 insert into public.competitors(event_id,display_name,kind,auth_user_id)
 values(v_event.id,trim(p_display_name),p_kind,auth.uid()) returning id into v_id;
 if p_kind='team' then
  foreach v_member in array coalesce(p_members,'{}') loop
   if length(trim(v_member))>0 then insert into public.team_members(team_id,member_name) values(v_id,trim(v_member)) on conflict do nothing; end if;
  end loop;
 end if;
 return v_id;
end; $$;

create or replace function public.organizer_set_event_status(p_event_id uuid,p_status public.event_status)
returns void language plpgsql security definer set search_path=public as $$
begin
 update public.events set status=p_status where id=p_event_id and created_by=auth.uid();
 if not found then raise exception 'Event not found or access denied'; end if;
end; $$;
create or replace function public.organizer_set_question(p_event_id uuid,p_question integer)
returns void language plpgsql security definer set search_path=public as $$
begin
 if p_question not between 0 and 10 then raise exception 'Question number must be 0-10'; end if;
 update public.events set current_question=p_question where id=p_event_id and created_by=auth.uid();
 if not found then raise exception 'Event not found or access denied'; end if;
end; $$;

revoke all on function public.create_event(text,text,integer) from public;
revoke all on function public.get_live_event_by_pin(text) from public;
revoke all on function public.join_event(text,text,public.competitor_kind,text[]) from public;
revoke all on function public.organizer_set_event_status(uuid,public.event_status) from public;
revoke all on function public.organizer_set_question(uuid,integer) from public;
grant execute on function public.create_event(text,text,integer) to authenticated;
grant execute on function public.get_live_event_by_pin(text) to anon,authenticated;
grant execute on function public.join_event(text,text,public.competitor_kind,text[]) to anon,authenticated;
grant execute on function public.organizer_set_event_status(uuid,public.event_status) to authenticated;
grant execute on function public.organizer_set_question(uuid,integer) to authenticated;

-- Enable Realtime for live organizer/participant views.
do $$ begin alter publication supabase_realtime add table public.events; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.competitors; exception when duplicate_object then null; end $$;
