-- Mise à jour : fenêtre fixe de 20 % et nouveau calcul des points.
-- À coller dans Supabase > SQL Editor puis Run (une seule fois).

create or replace function public.submit_answer(p_aid bigint, p_lo float8, p_hi float8, p_exact boolean default false) returns json
language plpgsql security definer set search_path = public as $$
-- Fourchette fixe (20 % de l'échelle, 10/8/6 % en survie) : 100 points si la bonne réponse est au centre,
-- 50 au bord, 0 dehors. Valeur exacte : 150 points.
declare uid uuid := public._me(); a public.attempts; q public.questions;
  v_el float8; v_late boolean; v_in boolean; v_pts int; v_tier text;
  plo float8; phi float8; pt float8; w float8; maxw float8; c float8;
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
    if q.kind = 'lin' then
      plo := (p_lo - q.vmin) / (q.vmax - q.vmin); phi := (p_hi - q.vmin) / (q.vmax - q.vmin); pt := (q.truth - q.vmin) / (q.vmax - q.vmin);
    else
      plo := ln(p_lo / q.vmin) / ln(q.vmax / q.vmin); phi := ln(p_hi / q.vmin) / ln(q.vmax / q.vmin); pt := ln(q.truth / q.vmin) / ln(q.vmax / q.vmin);
    end if;
    w := phi - plo;
    -- largeur imposée (marge pour les arrondis d'affichage)
    maxw := case when a.mode = 'surv' then 0.10 else 0.20 end + 0.05
            + case when q.kind = 'lin' then 1.0 / (q.vmax - q.vmin) else 0 end;
    if w > maxw then raise exception 'Fourchette trop large'; end if;
    v_in := q.truth between p_lo and p_hi;
    if v_in then
      c := greatest(0, least(1, 1 - abs(pt - (plo + phi) / 2) / greatest(w / 2, 1e-9)));
      v_pts := round(50 + 50 * c);
      v_tier := case when v_pts >= 80 then 'tight' else 'wide' end;
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

grant execute on function public.submit_answer(bigint, float8, float8, boolean) to authenticated;
