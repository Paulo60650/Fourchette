-- =====================================================================
-- La Fourchette : mise à jour « addictif »
-- Combo de centrage, mode Expert, divisions hebdomadaires, saisons
-- mensuelles, collection de cartes.
-- À coller dans Supabase > SQL Editor puis Run (après 01 à 03). Peut être relancé.
-- =====================================================================

-- ---------- Colonnes et tables ---------------------------------------

alter table public.attempts add column if not exists centr float8;
alter table public.attempts add column if not exists base_pts int;
alter table public.attempts add column if not exists mult numeric(3,1);
alter table public.attempts add column if not exists combo int;
alter table public.attempts drop constraint if exists attempts_mode_check;
alter table public.attempts add constraint attempts_mode_check check (mode in ('play','daily','surv','duel','expert'));

alter table public.profiles add column if not exists division text not null default 'bronze';
alter table public.profiles add column if not exists div_note text;

create table if not exists public.division_members(
  week date not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  tier text not null,
  grp int not null,
  primary key (week, user_id)
);
create index if not exists division_members_grp on public.division_members(week, tier, grp);

create table if not exists public.season_results(
  season date not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  rank int not null,
  total int not null,
  tier text not null,
  seen boolean not null default false,
  primary key (season, user_id)
);

alter table public.division_members enable row level security;
alter table public.season_results enable row level security;
revoke all on public.division_members, public.season_results from anon, authenticated;

-- ---------- Outils ----------------------------------------------------

create or replace function public._week() returns date language sql stable as
  $$ select date_trunc('week', now() at time zone 'Europe/Paris')::date $$;
create or replace function public._season() returns date language sql stable as
  $$ select date_trunc('month', now() at time zone 'Europe/Paris')::date $$;
-- début (instant) d'une date de Paris
create or replace function public._paris(d date) returns timestamptz language sql stable as
  $$ select d::timestamp at time zone 'Europe/Paris' $$;
create or replace function public._ranked() returns text[] language sql immutable as
  $$ select array['play','daily','expert'] $$;

-- Nombre de réponses classées : sert à débloquer le mode Expert.
create or replace function public._ranked_count(uid uuid) returns int language sql stable as $$
  select count(*)::int from public.attempts where user_id = uid and mode = any(public._ranked()) and answered_at is not null
$$;

-- ---------- Divisions hebdomadaires ------------------------------------
-- Groupes de 30 joueurs du même palier. Classement = total de points de la semaine.
-- À la première partie classée d'une nouvelle semaine, on regarde la semaine précédente :
-- top 5 = promotion, 5 derniers (groupe d'au moins 10) = relégation.

create or replace function public._tier_up(t text) returns text language sql immutable as $$
  select case t when 'bronze' then 'argent' when 'argent' then 'or' when 'or' then 'diamant' else 'diamant' end $$;
create or replace function public._tier_down(t text) returns text language sql immutable as $$
  select case t when 'diamant' then 'or' when 'or' then 'argent' when 'argent' then 'bronze' else 'bronze' end $$;

create or replace function public._group_board(p_week date, p_tier text, p_grp int)
returns table(user_id uuid, pts bigint, n bigint, rk bigint, size bigint)
language sql stable security definer set search_path = public as $$
  with m as (select dm.user_id from public.division_members dm where dm.week = p_week and dm.tier = p_tier and dm.grp = p_grp),
  s as (
    select m.user_id, coalesce(sum(a.pts), 0) pts, count(a.id) n
    from m left join public.attempts a on a.user_id = m.user_id and a.mode = any(public._ranked())
      and a.served_at >= public._paris(p_week) and a.served_at < public._paris(p_week + 7) and public._resolved(a)
    group by m.user_id
  )
  select s.user_id, s.pts, s.n, rank() over (order by s.pts desc), count(*) over () from s
$$;

create or replace function public._div_join(uid uuid) returns void
language plpgsql security definer set search_path = public as $$
declare w date := public._week(); last public.division_members; t text; g int; r record; note text := null;
begin
  if exists(select 1 from public.division_members where week = w and user_id = uid) then return; end if;
  select division into t from public.profiles where id = uid;
  t := coalesce(t, 'bronze');
  select * into last from public.division_members where user_id = uid and week < w order by week desc limit 1;
  if found then
    select * into r from public._group_board(last.week, last.tier, last.grp) b where b.user_id = uid;
    if r.rk <= 5 and r.pts > 0 and last.tier <> 'diamant' then
      t := public._tier_up(last.tier); note := 'promu:' || t;
    elsif r.size >= 10 and r.rk > r.size - 5 and last.tier <> 'bronze' then
      t := public._tier_down(last.tier); note := 'relegue:' || t;
    else
      t := last.tier; note := 'maintenu:' || t;
    end if;
  end if;
  select dm.grp into g from public.division_members dm where dm.week = w and dm.tier = t
    group by dm.grp having count(*) < 30 order by dm.grp limit 1;
  if g is null then
    select coalesce(max(dm.grp), 0) + 1 into g from public.division_members dm where dm.week = w and dm.tier = t;
  end if;
  insert into public.division_members(week, user_id, tier, grp) values (w, uid, t, g) on conflict do nothing;
  update public.profiles set division = t, div_note = coalesce(note, div_note) where id = uid;
end $$;

create or replace function public.division_status() returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); w date := public._week(); m public.division_members; res json; v_note text;
begin
  select * into m from public.division_members where week = w and user_id = uid;
  select div_note into v_note from public.profiles where id = uid;
  update public.profiles set div_note = null where id = uid and div_note is not null;
  if m.user_id is null then
    return json_build_object('joined', false, 'tier', (select division from public.profiles where id = uid),
      'ends', public._paris(w + 7), 'note', v_note);
  end if;
  with b as (select * from public._group_board(w, m.tier, m.grp)),
  me as (select * from b where user_id = uid),
  rival as (
    select p.pseudo, b.pts from b join public.profiles p on p.id = b.user_id, me
    where b.pts > me.pts order by b.pts asc, p.pseudo limit 1
  )
  select json_build_object('joined', true, 'tier', m.tier, 'grp', m.grp, 'ends', public._paris(w + 7), 'note', v_note,
    'size', (select count(*) from b),
    'me', (select json_build_object('rank', rk, 'pts', pts, 'n', n) from me),
    'rival', (select json_build_object('pseudo', rival.pseudo, 'gap', rival.pts - me.pts + 1) from rival, me),
    'members', (select coalesce(json_agg(json_build_object('pseudo', p.pseudo, 'v', b.pts, 'n', b.n, 'rank', b.rk, 'me', b.user_id = uid) order by b.rk, p.pseudo), '[]')
                from b join public.profiles p on p.id = b.user_id))
  into res;
  return res;
end $$;

-- ---------- Saisons mensuelles -------------------------------------------
-- Classement Niveau du mois (min. 10 questions). Au premier appel du mois suivant,
-- le résultat de la saison passée est figé et un badge est attribué.

create or replace function public._season_rank(p_season date)
returns table(user_id uuid, v float8, n bigint, rk bigint, tot bigint)
language sql stable security definer set search_path = public as $$
  with a as (
    select at.user_id, sum(coalesce(at.pts, 0))::float8 / count(*) v, count(*) n
    from public.attempts at
    where at.mode = any(public._ranked()) and public._resolved(at)
      and at.served_at >= public._paris(p_season) and at.served_at < public._paris((p_season + interval '1 month')::date)
    group by at.user_id having count(*) >= 10
  )
  select a.user_id, a.v, a.n, rank() over (order by a.v desc), count(*) over () from a
$$;

create or replace function public.season_status() returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); s date := public._season(); prev date := (public._season() - interval '1 month')::date;
  r record; v_tier text; news json; cur record;
begin
  if not exists(select 1 from public.season_results where season = prev and user_id = uid) then
    select * into r from public._season_rank(prev) x where x.user_id = uid;
    if found then
      v_tier := case when r.rk <= greatest(1, ceil(r.tot * 0.01)) then 'legende'
                     when r.rk <= ceil(r.tot * 0.10) then 'or'
                     when r.rk <= ceil(r.tot * 0.50) then 'argent' else 'bronze' end;
      insert into public.season_results(season, user_id, rank, total, tier) values (prev, uid, r.rk, r.tot, v_tier) on conflict do nothing;
    end if;
  end if;
  select coalesce(json_agg(json_build_object('season', season, 'rank', rank, 'total', total, 'tier', tier) order by season), '[]') into news
    from public.season_results where user_id = uid and not seen;
  update public.season_results set seen = true where user_id = uid and not seen;
  select * into cur from public._season_rank(s) x where x.user_id = uid;
  return json_build_object('season', s, 'ends', public._paris((s + interval '1 month')::date),
    'rank', cur.rk, 'total', cur.tot, 'v', round(cur.v::numeric, 1), 'news', news,
    'history', (select coalesce(json_agg(json_build_object('season', season, 'rank', rank, 'total', total, 'tier', tier) order by season desc), '[]')
                from public.season_results where user_id = uid));
end $$;

-- ---------- Collection : une carte par question réussie --------------------

create or replace function public.collection() returns json
language sql security definer set search_path = public as $$
  with u as (select distinct a.qid from public.attempts a where a.user_id = public._me() and a.inside)
  select coalesce(json_agg(json_build_object('theme', t.theme, 'total', t.total, 'unlocked', t.unlocked) order by t.theme), '[]')
  from (
    select q.theme, count(*) total, count(u.qid) unlocked
    from public.questions q left join u on u.qid = q.id where q.active group by q.theme
  ) t
$$;

create or replace function public.my_cards(p_theme text, p_offset int default 0) returns json
language sql security definer set search_path = public as $$
  with u as (
    select a.qid, max(coalesce(a.centr, 0)) best from public.attempts a
    where a.user_id = public._me() and a.inside group by a.qid
  )
  select coalesce(json_agg(json_build_object('i', q.id, 't', q.t, 'u', q.unit, 'v', q.truth, 'f', q.fmt, 'x', q.fact,
      'best', round(u.best::numeric, 2)) order by q.id), '[]')
  from (select * from u) u join public.questions q on q.id = u.qid
  where q.theme = p_theme
  limit 300
$$;

-- ---------- Tirage : mode Expert ----------------------------------------

create or replace function public.next_question(p_mode text, p_theme text default null, p_qid text default null) returns json
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
  insert into public.attempts(user_id, qid, mode) values (uid, q.id, p_mode) returning id into aid;
  return json_build_object('aid', aid, 'tl', public._tl(), 'elapsed', 0, 'q', public._qjson(q));
end $$;

-- ---------- Réponse : centrage, combo, Expert, division ------------------
-- Fenêtre 20 % (Expert 10 %, survie 10/8/6 %) : base = 50 + 50 × centrage si dedans, 0 dehors ;
-- valeur exacte = 150. Expert : base × 2.
-- Combo (parties classées) : réponses successives centrées à 80 % ou plus (ou exactes),
-- moins de 15 min d'écart : ×1 puis ×1,2, ×1,5, ×2. Une réponse décentrée remet à zéro.

create or replace function public.submit_answer(p_aid bigint, p_lo float8, p_hi float8, p_exact boolean default false) returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); a public.attempts; q public.questions; prev public.attempts;
  v_el float8; v_late boolean; v_in boolean; v_base int; v_pts int; v_tier text; v_c float8 := null;
  plo float8; phi float8; pt float8; w float8; maxw float8; k int := 0; v_mult numeric := 1; v_combo int := 0; good boolean := false; v_crowd json;
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
    v_base := 0; v_in := false; v_tier := 'out';
  elsif coalesce(p_exact, false) then
    v_in := case when q.kind = 'lin' then abs(p_lo - q.truth) < 0.5 else abs(p_lo / q.truth - 1) < 0.005 end;
    v_base := case when v_in then 150 else 0 end;
    v_tier := case when v_in then 'tight' else 'out' end;
    v_c := case when v_in then 1 else null end;
  else
    if q.kind = 'lin' then
      plo := (p_lo - q.vmin) / (q.vmax - q.vmin); phi := (p_hi - q.vmin) / (q.vmax - q.vmin); pt := (q.truth - q.vmin) / (q.vmax - q.vmin);
    else
      plo := ln(p_lo / q.vmin) / ln(q.vmax / q.vmin); phi := ln(p_hi / q.vmin) / ln(q.vmax / q.vmin); pt := ln(q.truth / q.vmin) / ln(q.vmax / q.vmin);
    end if;
    w := phi - plo;
    maxw := case when a.mode in ('surv', 'expert') then 0.10 else 0.20 end + 0.05
            + case when q.kind = 'lin' then 1.0 / (q.vmax - q.vmin) else 0 end;
    if w > maxw then raise exception 'Fourchette trop large'; end if;
    v_in := q.truth between p_lo and p_hi;
    if v_in then
      v_c := greatest(0, least(1, 1 - abs(pt - (plo + phi) / 2) / greatest(w / 2, 1e-9)));
      v_base := round(50 + 50 * v_c);
      v_tier := case when v_base >= 90 then 'tight' else 'wide' end;
    else
      v_base := 0; v_tier := 'out';
    end if;
  end if;
  if a.mode = 'expert' then v_base := v_base * 2; end if;
  v_pts := v_base;
  if a.mode = any(public._ranked()) then
    good := v_in and coalesce(v_c, 0) >= 0.8;
    select * into prev from public.attempts
      where user_id = uid and mode = any(public._ranked()) and answered_at is not null and id <> a.id
      order by answered_at desc, id desc limit 1;
    if found and prev.answered_at > now() - interval '15 minutes' and coalesce(prev.combo, 0) > 0 then k := prev.combo; end if;
    if good then
      v_combo := k + 1;
      v_mult := case when k <= 0 then 1 when k = 1 then 1.2 when k = 2 then 1.5 else 2 end;
      v_pts := round(v_base * v_mult);
    else
      v_combo := 0; v_mult := 1;
    end if;
    perform public._div_join(uid);
  end if;
  update public.attempts set answered_at = now(), lo = p_lo, hi = p_hi, exact = coalesce(p_exact, false),
    pts = v_pts, base_pts = v_base, inside = v_in, late = v_late, centr = v_c, mult = v_mult, combo = v_combo
  where id = a.id;
  -- la vraie foule : centre des réponses des autres joueurs (position 0 à 1 sur l'échelle)
  select coalesce(json_agg(round(z.c::numeric, 3)), '[]') into v_crowd from (
    select case when q.kind = 'lin' then ((x.lo + x.hi) / 2 - q.vmin) / (q.vmax - q.vmin)
                else (ln(x.lo / q.vmin) + ln(x.hi / q.vmin)) / 2 / ln(q.vmax / q.vmin) end c
    from public.attempts x
    where x.qid = q.id and x.id <> a.id and x.answered_at is not null and x.lo is not null and x.lo > 0
    order by x.answered_at desc limit 300) z;
  return json_build_object('truth', q.truth, 'fact', q.fact, 'pts', v_pts, 'base', v_base, 'inside', v_in, 'tier', v_tier,
    'late', v_late, 'elapsed', round(v_el::numeric, 1), 'mode', a.mode, 'centr', round(coalesce(v_c, 0)::numeric, 3),
    'mult', v_mult, 'combo', v_combo, 'crowd', v_crowd);
end $$;

-- ---------- Classements : « saison » = mois en cours ; mode Expert inclus ----

create or replace function public.world_board(p_period text default 'week', p_theme text default null,
  p_kind text default 'avg', p_country text default null, p_limit int default 20) returns json
language sql security definer set search_path = public as $$
  with a as (
    select at.user_id, coalesce(sum(at.pts), 0) s, count(*) n
    from public.attempts at join public.questions q on q.id = at.qid
    where at.mode = any(public._ranked())
      and at.served_at >= case when p_period = 'week' then now() - interval '7 days' else public._paris(public._season()) end
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
    'rival', (select json_build_object('pseudo', r2.pseudo, 'gap', round((r2.v - me.v)::numeric, 1))
              from r me join r r2 on r2.v > me.v where me.user_id = auth.uid() order by r2.v asc limit 1),
    'total', (select count(*) from r),
    'my_n', coalesce((select n from a where user_id = auth.uid()), 0))
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
    where at.mode = any(public._ranked()) and public._resolved(at)
      and at.served_at >= case when p_period = 'week' then now() - interval '7 days' else public._paris(public._season()) end
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

create or replace function public.get_profile() returns json
language sql security definer set search_path = public as $$
  select json_build_object('pseudo', p.pseudo, 'country', p.country, 'division', p.division,
    'answered', (select count(*) from public.attempts a where a.user_id = p.id and a.answered_at is not null),
    'ranked', public._ranked_count(p.id))
  from public.profiles p where p.id = public._me()
$$;

-- ---------- Droits -------------------------------------------------------

revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.set_profile(text, text), public.get_profile(), public.delete_my_account(),
  public.next_question(text, text, text), public.submit_answer(bigint, float8, float8, boolean),
  public.daily_next(), public.daily_status(), public.daily_board(int),
  public.world_board(text, text, text, text, int),
  public.create_league(text), public.join_league(text), public.leave_league(uuid),
  public.my_leagues(), public.league_board(uuid, text),
  public.division_status(), public.season_status(), public.collection(), public.my_cards(text, int)
to authenticated;
