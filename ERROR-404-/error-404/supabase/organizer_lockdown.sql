-- ERROR-404: restrict organizer powers to an allow-list. Run once in Supabase SQL Editor (after schema.sql).
create table if not exists public.organizers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text
);
alter table public.organizers enable row level security;
drop policy if exists "organizer reads own row" on public.organizers;
create policy "organizer reads own row" on public.organizers for select to authenticated using (user_id = auth.uid());

create or replace function public.is_organizer() returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.organizers where user_id = auth.uid());
$$;
revoke all on function public.is_organizer() from public;
grant execute on function public.is_organizer() to authenticated;

-- Only allow-listed organizers can create events
create or replace function public.create_event(p_name text,p_pin text,p_question_seconds integer default 300)
returns setof public.events language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or not public.is_organizer() then raise exception 'Organizer access only'; end if;
 if length(trim(p_name))=0 or p_pin !~ '^[0-9]{4,8}$' then raise exception 'Enter an event name and a 4-8 digit PIN'; end if;
 return query insert into public.events(name,pin,question_seconds,created_by)
 values(trim(p_name),p_pin,greatest(30,least(p_question_seconds,3600)),auth.uid()) returning *;
end; $$;

-- Extra guard: signed-in non-organizers get nothing from the events table
drop policy if exists "only organizers touch events" on public.events;
create policy "only organizers touch events" on public.events as restrictive for all to authenticated
  using (public.is_organizer()) with check (public.is_organizer());

-- Add your organizer account (create the user first in Authentication -> Users):
-- insert into public.organizers(user_id,email) select id,email from auth.users where email = 'YOUR_ORGANIZER_EMAIL';
