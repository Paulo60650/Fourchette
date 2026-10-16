-- La Fourchette · 06 : retour à la fourchette libre (à coller après 05_progression.sql, relançable)
-- La fourchette part au milieu, à sa largeur minimale (3 % de l'échelle). Le joueur choisit sa largeur.
-- Dedans : base = 100 × ((1 − w) / 0,965)², w = largeur en part de l'échelle (au moins 3,5 %, marge d'arrondi) :
--   100 à 3 %, 87 à 10 %, 69 à 20 %, 52 à 30 %, 27 à 50 %. Dehors : 0. Valeur exacte : 150.
-- Expert : largeur 10 % au plus, points × 2. Survie : inchangée (fourchette fixe 10/8/6 %).
-- « centr » contient désormais la précision (base / 100) : combo, badge Tir groupé (≥ 0,8, soit 13 % ou moins),
-- mission c90 (≥ 0,9, soit 8 % ou moins) et collection s'appuient dessus sans autre changement.
-- « wid » garde la largeur choisie, pour mesurer la calibration.

alter table public.attempts add column if not exists wid float8;

create or replace function public.submit_answer(p_aid bigint, p_lo float8, p_hi float8, p_exact boolean default false) returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := public._me(); a public.attempts; q public.questions; prev public.attempts;
  v_el float8; v_late boolean; v_in boolean; v_base int; v_pts int; v_tier text; v_c float8 := null;
  plo float8; phi float8; pt float8; w float8; we float8; maxw float8; k int := 0; v_mult numeric := 1; v_combo int := 0; good boolean := false; v_crowd json;
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
    -- largeur : survie fixe (10/8/6 %), Expert 10 % au plus, sinon libre (marge d'arrondi)
    maxw := case when a.mode in ('surv', 'expert') then 0.10 + 0.02 + case when q.kind = 'lin' then 1.0 / (q.vmax - q.vmin) else 0.005 end else 1.0 end;
    if w > maxw then raise exception 'Fourchette trop large'; end if;
    we := greatest(0.035, least(1.0, w));   -- 3 % + marge d'arrondi
    v_in := q.truth between p_lo and p_hi;
    if v_in then
      v_c := power((1 - we) / 0.965, 2);   -- précision : 1 à 3 % de l'échelle, ~0,5 à 30 %, 0 à 100 %
      v_base := round(100 * v_c);
      v_tier := case when v_c >= 0.8 then 'tight' else 'wide' end;
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
    pts = v_pts, base_pts = v_base, inside = v_in, late = v_late, centr = v_c, mult = v_mult, combo = v_combo,
    wid = case when coalesce(p_exact, false) or v_late then null else w end
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

grant execute on function public.submit_answer(bigint, float8, float8, boolean) to authenticated;

-- ---------- Profil : calibration (taux de réussite + largeur moyenne) ------

create or replace function public.my_stats() returns json
language sql security definer set search_path = public as $$
  with a as (
    select x.*, q.theme from public.attempts x join public.questions q on q.id = x.qid
    where x.user_id = public._me() and x.answered_at is not null and x.mode <> 'surv'
  ), l50 as (select inside, wid from a where not coalesce(exact, false) order by answered_at desc limit 50)
  select json_build_object(
    'n', (select count(*) from a),
    'games', (select count(distinct game_id) from a where game_id is not null),
    'best_game', (select max(s) from (select sum(pts) s from a where game_id is not null group by game_id) g),
    'last50', json_build_object('n', (select count(*) from l50), 'hits', (select count(*) from l50 where inside),
                                'avgw', (select round(avg(wid)::numeric, 3) from l50 where wid is not null)),
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
grant execute on function public.my_stats() to authenticated;
