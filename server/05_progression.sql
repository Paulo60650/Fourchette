-- =====================================================================
-- La Fourchette : progression sur le serveur
-- XP, badges, missions, coffre, jokers, série du défi et statistiques du
-- profil sont calculés ici à partir des réponses : rien n'est truquable
-- depuis le téléphone, et tout se retrouve sur un nouvel appareil.
-- À coller dans Supabase > SQL Editor puis Run (après 01 à 04). Peut être relancé.
-- =====================================================================

alter table public.attempts add column if not exists game_id uuid;
create index if not exists attempts_game on public.attempts(user_id, game_id);

create table if not exists public.player_progress(
  user_id uuid primary key references auth.users(id) on delete cascade,
  xp_bonus int not null default 0,
  jokers int not null default 0,
  chest_last date,
  tints jsonb not null default '{}',
  badges jsonb not null default '{}',
  mis_week date,
  mis_done jsonb not null default '[]',
  daily_last date,
  daily_streak int not null default 0,
  daily_best int not null default 0,
  daily_note text,
  duel_played int not null default 0,
  duel_won int not null default 0,
  duel_seen jsonb not null default '{}',
  duel_wins jsonb not null default '[]',
  updated_at timestamptz not null default now()
);
alter table public.player_progress enable row level security;
revoke all on public.player_progress from anon, authenticated;

create or replace function public._pp(uid uuid) returns public.player_progress
language plpgsql security definer set search_path = public as $$
declare r public.player_progress;
begin
  insert into public.player_progress(user_id) values (uid) on conflict do nothing;
  select * into r from public.player_progress where user_id = uid;
  return r;
end $$;

-- ---------- Tirage : identifiant de partie (pour badges et survie) ------

drop function if exists public.next_question(text, text, text);
create or replace function public.next_question(p_mode text, p_theme text default null, p_qid text default null, p_game uuid default null) returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); q public.questions; aid bigint; recent int;
begin
  if p_mode not in ('play', 'surv', 'duel', 'expert') then raise exception 'Mode inconnu'; end if;
  if p_mode = 'expert' and public._ranked_count(uid) < 80 then
    raise exception 'Mode Expert : répondez d''abord à 80 questions classées';
  end if;
  select count(*) into recent from public.attempts where user_id = uid and served_at > now() - interval '1 hour';
  if recent >= 400 then raise exception 'Beaucoup de questions en peu de temps : faites une pause'; end if;
  if p_qid is not null then
    if p_mode <> 'duel' then raise exception 'Question imposée réservée aux duels'; end if;
    select * into q from public.questions where id = p_qid and active;
    if not found then raise exception 'Question introuvable (duel d''une autre version ?)'; end if;
  else
    select qq.* into q from public.questions qq
    where qq.active and (p_theme is null or qq.theme = p_theme)
    order by (select max(a.served_at) from public.attempts a where a.user_id = uid and a.qid = qq.id) asc nulls first, random()
    limit 1;
    if not found then raise exception 'Aucune question disponible'; end if;
  end if;
  insert into public.attempts(user_id, qid, mode, game_id) values (uid, q.id, p_mode, p_game) returning id into aid;
  return json_build_object('aid', aid, 'tl', public._tl(), 'elapsed', 0, 'q', public._qjson(q));
end $$;

-- ---------- Série du défi du jour, avec jokers --------------------------

-- Jours où le joueur a terminé (5 réponses résolues) le défi.
create or replace function public._daily_days(uid uuid) returns table(day date, perfect boolean)
language sql stable security definer set search_path = public as $$
  select a.day, bool_and(coalesce(a.inside, false)) from public.attempts a
  where a.user_id = uid and a.mode = 'daily' and public._resolved(a)
  group by a.day having count(*) >= 5
$$;

-- Avance la série jour par jour ; un trou est comblé par des jokers s'il y en a assez.
create or replace function public._daily_sync(uid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare p public.player_progress; d record; gap int; missed int;
begin
  p := public._pp(uid);
  for d in select day from public._daily_days(uid) x where p.daily_last is null or x.day > p.daily_last order by day loop
    if p.daily_last is null then p.daily_streak := 1;
    else
      gap := d.day - p.daily_last;
      if gap = 1 then p.daily_streak := p.daily_streak + 1;
      else
        missed := gap - 1;
        if p.daily_streak > 0 and missed <= p.jokers then
          p.jokers := p.jokers - missed; p.daily_streak := p.daily_streak + 1;
          p.daily_note := 'joker:' || missed || ':' || p.daily_streak;
        else p.daily_streak := 1; end if;
      end if;
    end if;
    p.daily_last := d.day;
    p.daily_best := greatest(p.daily_best, p.daily_streak);
    if p.daily_streak % 7 = 0 and p.jokers < 3 then p.jokers := p.jokers + 1; end if;
  end loop;
  update public.player_progress set daily_last = p.daily_last, daily_streak = p.daily_streak, daily_best = p.daily_best,
    jokers = p.jokers, daily_note = p.daily_note, updated_at = now() where user_id = uid;
end $$;

-- ---------- Mesures servant aux badges ------------------------------------

create or replace function public._metrics(uid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m jsonb; p public.player_progress;
begin
  p := public._pp(uid);
  with a as (
    select x.*, q.theme, extract(epoch from x.answered_at - x.served_at) el
    from public.attempts x join public.questions q on q.id = x.qid
    where x.user_id = uid and x.answered_at is not null
  ), ns as (select * from a where mode <> 'surv'),
  runs as (
    select count(*) c from (
      select inside, row_number() over (order by answered_at) - row_number() over (partition by inside order by answered_at) g from ns
    ) r where inside group by g
  ),
  days as (
    select count(*) c from (
      select d, d - (row_number() over (order by d))::int g
      from (select distinct (answered_at at time zone 'Europe/Paris')::date d from a) z
    ) r group by g
  ),
  games as (
    select game_id, count(*) n, bool_and(coalesce(inside, false)) allin, avg(coalesce(pts, 0)) av
    from ns where game_id is not null and mode in ('play', 'expert') group by game_id
  ),
  surv as (select game_id, count(*) filter (where inside) c from a where mode = 'surv' and game_id is not null group by game_id),
  th as (select theme, count(*) n, avg(case when inside then 1 else 0 end) r from ns where not coalesce(exact, false) group by theme)
  select jsonb_build_object(
    'qn', (select count(*) from ns),
    'pts', (select coalesce(sum(pts), 0) from ns),
    'games', (select count(*) from games where n >= 3),
    'dstreak', (select coalesce(max(c), 0) from days),
    'exacts', (select count(*) from ns where exact and inside),
    't80', (select count(*) from ns where not coalesce(exact, false) and coalesce(centr, 0) >= 0.8),
    'cb2', (select count(*) from ns where coalesce(mult, 1) >= 2),
    'maxrun', (select coalesce(max(c), 0) from runs),
    'perf', (select count(*) from games where n >= 5 and allin),
    'gold', (select count(*) from games where n >= 5 and av >= 80),
    'mara', (select coalesce(max(n), 0) from games),
    'fast', (select count(*) from ns where inside and el <= 5),
    'last', (select count(*) from ns where inside and el >= public._tl() - 2 and el <= public._tl() + 1),
    'themes', (select count(distinct theme) from ns),
    'spe', (select count(*) from th where n >= 20 and r >= 0.75),
    'survbest', (select coalesce(max(c), 0) from surv),
    'daily_done', (select count(*) from public._daily_days(uid)),
    'daily_best', p.daily_best,
    'daily_perf', (select count(*) from public._daily_days(uid) where perfect),
    'duel_played', p.duel_played,
    'duel_won', p.duel_won,
    'expert', (select count(*) from a where mode = 'expert')
  ) into m;
  return m;
end $$;

create or replace function public._badge_defs() returns table(id text, metric text, target int)
language sql immutable as $$
  values ('q1','qn',1),('q10','qn',10),('q50','qn',50),('q100','qn',100),('q250','qn',250),('q500','qn',500),('q1000','qn',1000),
    ('g10','games',10),('g50','games',50),('d3','dstreak',3),('d7','dstreak',7),('d30','dstreak',30),
    ('p1k','pts',1000),('p10k','pts',10000),('p50k','pts',50000),('ex1','exacts',1),('ex10','exacts',10),
    ('t90','t80',1),('cb2','cb2',1),('exp','expert',1),('r5','maxrun',5),('r10','maxrun',10),('r20','maxrun',20),
    ('perf','perf',1),('gold','gold',1),('mara','mara',25),('fast','fast',1),('last','last',1),('all','themes',8),('spe','spe',1),
    ('dd1','daily_done',1),('dd7','daily_best',7),('dd30','daily_best',30),('ddp','daily_perf',1),
    ('du1','duel_played',1),('du5','duel_won',5),('s5','survbest',5),('s10','survbest',10),('s20','survbest',20),('s30','survbest',30)
$$;

-- ---------- Missions de la semaine ----------------------------------------

create or replace function public._mission_defs() returns table(id text, target int)
language sql immutable as $$
  values ('c90',10),('dd3',3),('duel1',1),('q60',60),('surv10',10),('ex2',2),('cb2',1),('th6',6)
$$;

create or replace function public._missions(uid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare w date := public._week(); t0 timestamptz := public._paris(public._week()); p public.player_progress; v jsonb;
begin
  p := public._pp(uid);
  with a as (
    select x.*, q.theme from public.attempts x join public.questions q on q.id = x.qid
    where x.user_id = uid and x.answered_at is not null and x.served_at >= t0
  ), cur as (
    select d.id, d.target, case d.id
      when 'c90' then (select count(*) from a where mode <> 'surv' and not coalesce(exact, false) and coalesce(centr, 0) >= 0.9)
      when 'dd3' then (select count(*) from public._daily_days(uid) x where x.day >= w)
      when 'duel1' then (select count(*) from jsonb_array_elements_text(p.duel_wins) e where e::timestamptz >= t0)
      when 'q60' then (select count(*) from a)
      when 'surv10' then (select coalesce(max(c), 0) from (select count(*) filter (where inside) c from a where mode = 'surv' and game_id is not null group by game_id) s)
      when 'ex2' then (select count(*) from a where exact and inside)
      when 'cb2' then (select count(*) from a where coalesce(mult, 1) >= 2)
      when 'th6' then (select count(distinct theme) from a)
    end::int c
    from public._mission_defs() d
    order by md5(w::text || d.id) limit 3
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'max', target, 'cur', least(c, target))), '[]') into v from cur;
  return v;
end $$;

-- ---------- Synchronisation : tout ce que l'appli affiche ------------------

create or replace function public.progress_sync() returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); p public.player_progress; m jsonb; ms jsonb; d record;
  newb text[] := '{}'; newm text[] := '{}'; b jsonb; done jsonb; xp bigint; today date := public._today();
  eff int; prot boolean := false; note text; e jsonb;
begin
  perform public._daily_sync(uid);
  p := public._pp(uid);
  m := public._metrics(uid);
  -- badges
  b := p.badges;
  for d in select * from public._badge_defs() loop
    if not (b ? d.id) and coalesce((m ->> d.metric)::int, 0) >= d.target then
      b := b || jsonb_build_object(d.id, (extract(epoch from now()) * 1000)::bigint);
      newb := newb || d.id;
    end if;
  end loop;
  -- missions
  if p.mis_week is distinct from public._week() then p.mis_week := public._week(); p.mis_done := '[]'; end if;
  done := p.mis_done;
  ms := public._missions(uid);
  for e in select * from jsonb_array_elements(ms) loop
    if (e ->> 'cur')::int >= (e ->> 'max')::int and not done ? (e ->> 'id') then
      done := done || to_jsonb(e ->> 'id'); newm := newm || (e ->> 'id'); p.xp_bonus := p.xp_bonus + 150;
    end if;
  end loop;
  if jsonb_array_length(ms) = 3 and not done ? 'all'
     and (select bool_and(done ? (x ->> 'id')) from jsonb_array_elements(ms) x) then
    done := done || '"all"'::jsonb; newm := newm || 'all'::text;
    if p.jokers < 3 then p.jokers := p.jokers + 1; end if;
  end if;
  note := p.daily_note;
  update public.player_progress set badges = b, mis_week = p.mis_week, mis_done = done, xp_bonus = p.xp_bonus,
    jokers = p.jokers, daily_note = null, updated_at = now() where user_id = uid;
  -- XP : réponses + défis terminés + badges + bonus (coffre, missions)
  select coalesce(sum(case when mode = 'surv' then case when inside then 20 else 0 end else 5 + coalesce(pts, 0) end), 0) into xp
    from public.attempts where user_id = uid and answered_at is not null;
  xp := xp + 100 * (m ->> 'daily_done')::int + 50 * (select count(*) from jsonb_object_keys(b)) + p.xp_bonus;
  -- série effective : protégée si les jours manqués sont couverts par les jokers
  if p.daily_last is null then eff := 0;
  elsif p.daily_last >= today - 1 then eff := p.daily_streak;
  elsif (today - 1 - p.daily_last) <= p.jokers and p.daily_streak > 0 then eff := p.daily_streak; prot := true;
  else eff := 0; end if;
  return json_build_object('xp', xp, 'jokers', p.jokers, 'chest_ready', p.chest_last is distinct from today,
    'tints', p.tints, 'badges', b, 'new_badges', to_json(newb), 'metrics', m,
    'missions', (select json_agg(x || jsonb_build_object('done', done ? (x ->> 'id'))) from jsonb_array_elements(ms) x),
    'new_missions', to_json(newm), 'all_missions', done ? 'all',
    'daily', json_build_object('streak', eff, 'best', p.daily_best, 'last', p.daily_last, 'protected', prot,
      'done_today', exists(select 1 from public._daily_days(uid) x where x.day = today), 'note', note),
    'duel', json_build_object('played', p.duel_played, 'won', p.duel_won),
    'ranked', public._ranked_count(uid));
end $$;

-- ---------- Coffre du jour (tirage côté serveur) -------------------------

create or replace function public.claim_chest() returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); p public.player_progress; r float8 := random(); res jsonb; locked text[]; t text;
begin
  perform public._pp(uid);
  select * into p from public.player_progress where user_id = uid for update;
  if p.chest_last = public._today() then raise exception 'Coffre déjà ouvert aujourd''hui'; end if;
  select array_agg(x) into locked from unnest(array['ocean','neon','sakura','aurore']) x where not p.tints ? x;
  if r < 0.45 then res := '{"xp":50}';
  elsif r < 0.70 then res := '{"xp":100}';
  elsif r < 0.80 then res := '{"xp":250}';
  elsif r < 0.92 then res := case when p.jokers < 3 then '{"joker":1}' else '{"xp":100}' end;
  elsif coalesce(array_length(locked, 1), 0) > 0 then
    t := locked[1 + floor(random() * array_length(locked, 1))::int]; res := jsonb_build_object('tint', t);
  else res := '{"xp":150}'; end if;
  update public.player_progress set chest_last = public._today(),
    xp_bonus = xp_bonus + coalesce((res ->> 'xp')::int, 0),
    jokers = jokers + coalesce((res ->> 'joker')::int, 0),
    tints = case when res ? 'tint' then tints || jsonb_build_object(res ->> 'tint', 1) else tints end,
    updated_at = now()
  where user_id = uid;
  return res;
end $$;

-- ---------- Duels (déclarés par l'appli, une seule fois par code) ----------

create or replace function public.report_duel(p_key text, p_won boolean) returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); p public.player_progress;
begin
  perform public._pp(uid);
  select * into p from public.player_progress where user_id = uid for update;
  if p_key is null or char_length(p_key) < 8 or p.duel_seen ? p_key then return json_build_object('counted', false); end if;
  update public.player_progress set duel_seen = duel_seen || jsonb_build_object(p_key, 1),
    duel_played = duel_played + 1, duel_won = duel_won + case when p_won then 1 else 0 end,
    duel_wins = case when p_won then duel_wins || to_jsonb(now()::text) else duel_wins end, updated_at = now()
  where user_id = uid;
  return json_build_object('counted', true);
end $$;

-- ---------- Statistiques du profil (tous appareils confondus) --------------

create or replace function public.my_stats() returns json
language sql security definer set search_path = public as $$
  with a as (
    select x.*, q.theme from public.attempts x join public.questions q on q.id = x.qid
    where x.user_id = public._me() and x.answered_at is not null and x.mode <> 'surv'
  ), l50 as (select inside from a where not coalesce(exact, false) order by answered_at desc limit 50)
  select json_build_object(
    'n', (select count(*) from a),
    'games', (select count(distinct game_id) from a where game_id is not null),
    'best_game', (select max(s) from (select sum(pts) s from a where game_id is not null group by game_id) g),
    'last50', json_build_object('n', (select count(*) from l50), 'hits', (select count(*) from l50 where inside)),
    'themes', (select coalesce(json_agg(json_build_object('theme', theme, 'n', n, 's', s, 'ne', ne, 'hits', hits) order by theme), '[]') from (
      select theme, count(*) n, sum(coalesce(pts, 0)) s,
        count(*) filter (where not coalesce(exact, false)) ne,
        count(*) filter (where not coalesce(exact, false) and inside) hits
      from a group by theme) t),
    'days', (select coalesce(json_agg(json_build_object('day', d, 'n', n, 'hits', h) order by d), '[]') from (
      select * from (
        select (answered_at at time zone 'Europe/Paris')::date d, count(*) n, count(*) filter (where inside) h
        from a where not coalesce(exact, false) group by 1 order by 1 desc limit 10) z) y)
  )
$$;

-- ---------- Droits -------------------------------------------------------

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.set_profile(text, text), public.get_profile(), public.delete_my_account(),
  public.next_question(text, text, text, uuid), public.submit_answer(bigint, float8, float8, boolean),
  public.daily_next(), public.daily_status(), public.daily_board(int),
  public.world_board(text, text, text, text, int),
  public.create_league(text), public.join_league(text), public.leave_league(uuid),
  public.my_leagues(), public.league_board(uuid, text),
  public.division_status(), public.season_status(), public.collection(), public.my_cards(text, int),
  public.progress_sync(), public.claim_chest(), public.report_duel(text, boolean), public.my_stats()
to authenticated;
