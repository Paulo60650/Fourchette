-- =====================================================================
-- La Fourchette : serveur (Supabase / Postgres)
-- À coller dans Supabase > SQL Editor, puis « Run ». Peut être relancé.
-- Ensuite : 02_questions_*.sql pour importer la banque de questions.
-- =====================================================================

-- (aucune extension nécessaire : gen_random_uuid() est intégré à Postgres)

-- ---------- Tables ----------------------------------------------------

create table if not exists public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  pseudo text not null default 'Joueur',
  country text not null default 'FR',
  created_at timestamptz not null default now()
);

-- La banque : jamais lisible directement par l'appli (pas de politique RLS).
create table if not exists public.questions(
  id text primary key,
  theme text not null,
  t text not null,
  unit text not null default '',
  kind text not null check (kind in ('lin','log')),
  vmin float8 not null,
  vmax float8 not null,
  truth float8 not null,
  sc float8 not null default 1,
  ticks jsonb not null default '[]',
  fmt text not null default 'i',
  fact text not null default '',
  is_int boolean not null default false,
  active boolean not null default true
);

-- Chaque question servie à un joueur, avec l'heure d'envoi : c'est le chrono serveur.
create table if not exists public.attempts(
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  qid text not null references public.questions(id),
  mode text not null check (mode in ('play','daily','surv','duel')),
  day date,
  served_at timestamptz not null default now(),
  answered_at timestamptz,
  lo float8, hi float8,
  exact boolean,
  pts int,
  inside boolean,
  late boolean
);
create index if not exists attempts_user_time on public.attempts(user_id, served_at desc);
create index if not exists attempts_mode_day on public.attempts(mode, day);
create index if not exists attempts_time on public.attempts(served_at);
create unique index if not exists attempts_daily_once on public.attempts(user_id, day, qid) where mode = 'daily';

-- Le défi du jour : les mêmes 5 questions pour tout le monde.
create table if not exists public.daily(
  day date primary key,
  qids text[] not null,
  created_at timestamptz not null default now()
);

create table if not exists public.leagues(
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 40),
  code text not null unique,
  owner uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create table if not exists public.league_members(
  league_id uuid not null references public.leagues(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (league_id, user_id)
);

-- ---------- Sécurité : tout passe par les fonctions ci-dessous -------

alter table public.profiles enable row level security;
alter table public.questions enable row level security;
alter table public.attempts enable row level security;
alter table public.daily enable row level security;
alter table public.leagues enable row level security;
alter table public.league_members enable row level security;

revoke all on public.questions, public.daily, public.leagues, public.league_members from anon, authenticated;
revoke all on public.profiles, public.attempts from anon;
revoke insert, update, delete on public.profiles, public.attempts from authenticated;

drop policy if exists "lecture pseudos" on public.profiles;
create policy "lecture pseudos" on public.profiles for select to authenticated using (true);
drop policy if exists "mes tentatives" on public.attempts;
create policy "mes tentatives" on public.attempts for select to authenticated using (user_id = auth.uid());

-- ---------- Profil créé automatiquement à l'inscription ---------------

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, pseudo)
  values (new.id, 'Joueur' || lpad((floor(random() * 10000))::int::text, 4, '0'))
  on conflict do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Outils internes -------------------------------------------

create or replace function public._tl() returns int language sql immutable as $$ select 25 $$;
create or replace function public._grace() returns int language sql immutable as $$ select 4 $$;
create or replace function public._today() returns date language sql stable as
  $$ select (now() at time zone 'Europe/Paris')::date $$;

create or replace function public._me() returns uuid
language plpgsql security definer set search_path = public as $$
declare v uuid := auth.uid();
begin
  if v is null then raise exception 'Non connecté'; end if;
  insert into public.profiles(id, pseudo)
  values (v, 'Joueur' || lpad((floor(random() * 10000))::int::text, 4, '0'))
  on conflict do nothing;
  return v;
end $$;

-- La question telle que l'appli la reçoit : sans la réponse ni l'anecdote.
create or replace function public._qjson(q public.questions) returns json
language sql immutable as $$
  select json_build_object('i', q.id, 'd', q.theme, 't', q.t, 'u', q.unit,
    'k', case when q.kind = 'lin' then 'y' else 'n' end,
    'a', q.vmin, 'b', q.vmax, 'c', q.sc, 'tk', q.ticks, 'f', q.fmt, 'n', case when q.is_int then 1 else 0 end)
$$;

-- Une réponse est « résolue » si elle a été donnée ou si le temps est écoulé (0 point).
create or replace function public._resolved(a public.attempts) returns boolean
language sql stable as $$
  select a.answered_at is not null or a.served_at < now() - make_interval(secs => public._tl() + public._grace())
$$;

create or replace function public._daily_ids(p_day date) returns text[]
language plpgsql security definer set search_path = public as $$
declare v text[];
begin
  select qids into v from public.daily where day = p_day;
  if v is null then
    insert into public.daily(day, qids)
    select p_day, array(
      select id from (
        select distinct on (theme) id, theme from public.questions where active order by theme, random()
      ) s order by random() limit 5)
    on conflict (day) do nothing;
    select qids into v from public.daily where day = p_day;
  end if;
  return v;
end $$;

-- ---------- Profil -----------------------------------------------------

create or replace function public.set_profile(p_pseudo text, p_country text default 'FR') returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); v text := btrim(coalesce(p_pseudo, ''));
begin
  if char_length(v) < 2 or char_length(v) > 20 then raise exception 'Pseudo : entre 2 et 20 caractères'; end if;
  if v !~ '^[[:alnum:] ._''-]+$' then raise exception 'Pseudo : lettres, chiffres, espace, point, tiret'; end if;
  if exists(select 1 from public.profiles where lower(pseudo) = lower(v) and id <> uid) then
    raise exception 'Ce pseudo est déjà pris';
  end if;
  update public.profiles set pseudo = v,
    country = case when upper(coalesce(p_country,'')) ~ '^[A-Z]{2}$' then upper(p_country) else country end
  where id = uid;
  return (select json_build_object('pseudo', pseudo, 'country', country) from public.profiles where id = uid);
end $$;

create or replace function public.get_profile() returns json
language sql security definer set search_path = public as $$
  select json_build_object('pseudo', p.pseudo, 'country', p.country,
    'answered', (select count(*) from public.attempts a where a.user_id = p.id and a.answered_at is not null))
  from public.profiles p where p.id = public._me()
$$;

-- Obligatoire pour le Play Store : supprimer son compte depuis l'appli.
create or replace function public.delete_my_account() returns json
language plpgsql security definer set search_path = public, auth as $$
declare uid uuid := public._me();
begin
  delete from auth.users where id = uid;
  return json_build_object('deleted', true);
end $$;

-- ---------- Jeu : tirer une question, répondre -------------------------

create or replace function public.next_question(p_mode text, p_theme text default null, p_qid text default null) returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); q public.questions; aid bigint; recent int;
begin
  if p_mode not in ('play', 'surv', 'duel') then raise exception 'Mode inconnu'; end if;
  select count(*) into recent from public.attempts where user_id = uid and served_at > now() - interval '1 hour';
  if recent >= 400 then raise exception 'Beaucoup de questions en peu de temps : faites une pause'; end if;
  if p_qid is not null then
    if p_mode <> 'duel' then raise exception 'Question imposée réservée aux duels'; end if;
    select * into q from public.questions where id = p_qid and active;
    if not found then raise exception 'Question introuvable (duel d''une autre version ?)'; end if;
  else
    -- jamais vue d'abord, sinon la plus anciennement vue
    select qq.* into q from public.questions qq
    where qq.active and (p_theme is null or qq.theme = p_theme)
    order by (select max(a.served_at) from public.attempts a where a.user_id = uid and a.qid = qq.id) asc nulls first, random()
    limit 1;
    if not found then raise exception 'Aucune question disponible'; end if;
  end if;
  insert into public.attempts(user_id, qid, mode) values (uid, q.id, p_mode) returning id into aid;
  return json_build_object('aid', aid, 'tl', public._tl(), 'elapsed', 0, 'q', public._qjson(q));
end $$;

create or replace function public.submit_answer(p_aid bigint, p_lo float8, p_hi float8, p_exact boolean default false) returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); a public.attempts; q public.questions;
  v_el float8; v_late boolean; v_in boolean; v_pts int; v_tier text; s float8;
begin
  select * into a from public.attempts where id = p_aid and user_id = uid for update;
  if not found then raise exception 'Question introuvable'; end if;
  if a.answered_at is not null then raise exception 'Déjà répondu'; end if;
  if p_lo is null or p_hi is null or p_hi < p_lo then raise exception 'Réponse invalide'; end if;
  select * into q from public.questions where id = a.qid;
  if q.kind = 'log' and p_lo <= 0 then raise exception 'Réponse invalide'; end if;
  v_el := extract(epoch from now() - a.served_at);
  v_late := v_el > public._tl() + public._grace();
  if v_late then
    v_pts := 0; v_in := false; v_tier := 'out';
  elsif coalesce(p_exact, false) then
    v_in := case when q.kind = 'lin' then abs(p_lo - q.truth) < 0.5 else abs(p_lo / q.truth - 1) < 0.005 end;
    v_pts := case when v_in then 150 else 0 end;
    v_tier := case when v_in then 'tight' else 'out' end;
  else
    v_in := q.truth between p_lo and p_hi;
    if v_in then
      s := case when q.kind = 'lin' then (p_hi - p_lo) / q.sc else ln(p_hi / p_lo) end;
      v_pts := round(100 * exp(-1.2 * s));
      v_tier := case when v_pts >= 70 then 'tight' else 'wide' end;
    else
      v_pts := 0; v_tier := 'out';
    end if;
  end if;
  update public.attempts set answered_at = now(), lo = p_lo, hi = p_hi, exact = coalesce(p_exact, false),
    pts = v_pts, inside = v_in, late = v_late
  where id = a.id;
  return json_build_object('truth', q.truth, 'fact', q.fact, 'pts', v_pts, 'inside', v_in, 'tier', v_tier,
    'late', v_late, 'elapsed', round(v_el::numeric, 1), 'mode', a.mode);
end $$;

-- ---------- Défi du jour : mêmes questions pour tous ------------------

create or replace function public.daily_next() returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); d date := public._today(); ids text[]; i int; a public.attempts; q public.questions; aid bigint;
begin
  ids := public._daily_ids(d);
  for i in 1 .. coalesce(array_length(ids, 1), 0) loop
    select * into a from public.attempts where user_id = uid and mode = 'daily' and day = d and qid = ids[i];
    if not found then
      select * into q from public.questions where id = ids[i];
      insert into public.attempts(user_id, qid, mode, day) values (uid, q.id, 'daily', d) returning id into aid;
      return json_build_object('aid', aid, 'idx', i, 'total', array_length(ids, 1), 'tl', public._tl(), 'elapsed', 0, 'q', public._qjson(q));
    elsif a.answered_at is null and a.served_at > now() - make_interval(secs => public._tl()) then
      -- reprise après fermeture de l'appli : même question, chrono qui continue
      select * into q from public.questions where id = ids[i];
      return json_build_object('aid', a.id, 'idx', i, 'total', array_length(ids, 1), 'tl', public._tl(),
        'elapsed', round(extract(epoch from now() - a.served_at)::numeric, 1), 'q', public._qjson(q));
    end if;
  end loop;
  return json_build_object('done', true, 'total', array_length(ids, 1));
end $$;

-- Où j'en suis aujourd'hui, et mon rang en direct après le même nombre de questions que moi.
create or replace function public.daily_status() returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); d date := public._today(); v_n int; v_s int; v_started int; v_rank int; v_players int; v_total int; v_finished int;
begin
  perform public._daily_ids(d);
  select count(*) filter (where public._resolved(a)), coalesce(sum(a.pts), 0), count(*)
    into v_n, v_s, v_started
  from public.attempts a where a.user_id = uid and a.mode = 'daily' and a.day = d;
  with o as (
    select a.user_id, coalesce(a.pts, 0) p, row_number() over (partition by a.user_id order by a.served_at) rn
    from public.attempts a where a.mode = 'daily' and a.day = d and public._resolved(a)
  ), t as (
    select user_id, sum(p) s, count(*) c from o where rn <= greatest(v_n, 1) group by user_id
  )
  select count(*) filter (where c >= greatest(v_n, 1)),
         1 + count(*) filter (where c >= greatest(v_n, 1) and s > v_s and user_id <> uid)
    into v_players, v_rank from t;
  select count(distinct user_id) into v_total from public.attempts where mode = 'daily' and day = d;
  select count(*) into v_finished from (
    select user_id from public.attempts a where a.mode = 'daily' and a.day = d and public._resolved(a)
    group by user_id having count(*) >= 5) f;
  return json_build_object('day', d, 'started', v_started > 0, 'answered', v_n, 'done', v_n >= 5, 'score', v_s,
    'rank', case when v_n > 0 then v_rank end, 'players_at_step', v_players, 'players', v_total, 'finished', v_finished);
end $$;

create or replace function public.daily_board(p_limit int default 20) returns json
language sql security definer set search_path = public as $$
  with s as (
    select a.user_id, coalesce(sum(a.pts), 0) sc, count(*) filter (where public._resolved(a)) n
    from public.attempts a where a.mode = 'daily' and a.day = public._today()
    group by a.user_id
  ), r as (
    select s.*, p.pseudo, p.country, rank() over (order by sc desc) rk, count(*) over () tot
    from s join public.profiles p on p.id = s.user_id
  )
  select json_build_object(
    'top', (select coalesce(json_agg(json_build_object('pseudo', pseudo, 'country', country, 'v', sc, 'n', n, 'rank', rk, 'me', user_id = auth.uid()) order by rk, pseudo), '[]')
            from (select * from r order by rk, pseudo limit greatest(1, least(p_limit, 100))) x),
    'me', (select json_build_object('rank', rk, 'v', sc, 'n', n, 'total', tot) from r where user_id = auth.uid()),
    'total', (select count(*) from r))
$$;

-- ---------- Classement mondial réel -----------------------------------
-- p_period : 'week' (7 jours) ou 'season' (28 jours) ; p_kind : 'avg' (niveau) ou 'cum' (cumulé)
create or replace function public.world_board(p_period text default 'week', p_theme text default null,
  p_kind text default 'avg', p_country text default null, p_limit int default 20) returns json
language sql security definer set search_path = public as $$
  with a as (
    select at.user_id, coalesce(sum(at.pts), 0) s, count(*) n
    from public.attempts at join public.questions q on q.id = at.qid
    where at.mode in ('play', 'daily')
      and at.served_at >= now() - case when p_period = 'week' then interval '7 days' else interval '28 days' end
      and public._resolved(at)
      and (p_theme is null or q.theme = p_theme)
    group by at.user_id
  ), b as (
    select a.*, p.pseudo, p.country,
      case when p_kind = 'cum' then a.s::float8 else a.s::float8 / a.n end v
    from a join public.profiles p on p.id = a.user_id
    where (p_country is null or p.country = p_country) and (p_kind = 'cum' or a.n >= 10)
  ), r as (
    select b.*, rank() over (order by v desc) rk, count(*) over () tot from b
  )
  select json_build_object(
    'top', (select coalesce(json_agg(json_build_object('pseudo', pseudo, 'country', country, 'v', round(v::numeric, 1), 'n', n, 'rank', rk, 'me', user_id = auth.uid()) order by rk, pseudo), '[]')
            from (select * from r order by rk, pseudo limit greatest(1, least(p_limit, 100))) x),
    'me', (select json_build_object('rank', rk, 'v', round(v::numeric, 1), 'n', n, 'total', tot) from r where user_id = auth.uid()),
    'total', (select count(*) from r),
    'my_n', coalesce((select n from a where user_id = auth.uid()), 0))
$$;

-- ---------- Ligues entre amis -----------------------------------------

create or replace function public.create_league(p_name text) returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); v_code text; v_id uuid; n int;
begin
  select count(*) into n from public.league_members where user_id = uid;
  if n >= 20 then raise exception 'Maximum 20 ligues'; end if;
  loop
    select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', (floor(random() * 31) + 1)::int, 1), '') into v_code from generate_series(1, 6);
    exit when char_length(v_code) = 6 and not exists(select 1 from public.leagues where code = v_code);
  end loop;
  insert into public.leagues(name, code, owner) values (btrim(p_name), v_code, uid) returning id into v_id;
  insert into public.league_members(league_id, user_id) values (v_id, uid);
  return json_build_object('id', v_id, 'name', btrim(p_name), 'code', v_code);
end $$;

create or replace function public.join_league(p_code text) returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); l public.leagues;
begin
  select * into l from public.leagues where code = upper(btrim(p_code));
  if not found then raise exception 'Code de ligue inconnu'; end if;
  if (select count(*) from public.league_members where league_id = l.id) >= 100 then raise exception 'Ligue complète'; end if;
  insert into public.league_members(league_id, user_id) values (l.id, uid) on conflict do nothing;
  return json_build_object('id', l.id, 'name', l.name, 'code', l.code);
end $$;

create or replace function public.leave_league(p_id uuid) returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me();
begin
  delete from public.league_members where league_id = p_id and user_id = uid;
  delete from public.leagues l where l.id = p_id and not exists(select 1 from public.league_members m where m.league_id = l.id);
  return json_build_object('left', true);
end $$;

create or replace function public.my_leagues() returns json
language sql security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('id', l.id, 'name', l.name, 'code', l.code,
    'members', (select count(*) from public.league_members m2 where m2.league_id = l.id)) order by m.joined_at), '[]')
  from public.league_members m join public.leagues l on l.id = m.league_id
  where m.user_id = public._me()
$$;

create or replace function public.league_board(p_id uuid, p_period text default 'week') returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); res json;
begin
  if not exists(select 1 from public.league_members where league_id = p_id and user_id = uid) then
    raise exception 'Vous ne faites pas partie de cette ligue';
  end if;
  with m as (select user_id from public.league_members where league_id = p_id),
  a as (
    select at.user_id, coalesce(sum(at.pts), 0) s, count(*) n
    from public.attempts at join m using (user_id)
    where at.mode in ('play', 'daily') and public._resolved(at)
      and at.served_at >= now() - case when p_period = 'week' then interval '7 days' else interval '28 days' end
    group by at.user_id
  )
  select coalesce(json_agg(json_build_object('pseudo', p.pseudo, 'country', p.country, 'n', coalesce(a.n, 0),
      'v', case when coalesce(a.n, 0) > 0 then round((a.s::float8 / a.n)::numeric, 1) else null end,
      'me', p.id = uid)
    order by (case when coalesce(a.n, 0) > 0 then a.s::float8 / a.n else -1 end) desc, p.pseudo), '[]')
  into res
  from m join public.profiles p on p.id = m.user_id left join a on a.user_id = m.user_id;
  return json_build_object('members', res);
end $$;

-- ---------- Droits : seules les fonctions publiques sont appelables ----

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.set_profile(text, text), public.get_profile(), public.delete_my_account(),
  public.next_question(text, text, text), public.submit_answer(bigint, float8, float8, boolean),
  public.daily_next(), public.daily_status(), public.daily_board(int),
  public.world_board(text, text, text, text, int),
  public.create_league(text), public.join_league(text), public.leave_league(uuid),
  public.my_leagues(), public.league_board(uuid, text)
to authenticated;
