-- Avoid PL/pgSQL record/alias ambiguity in the claim approval guard.
begin;
create or replace function public.langkah_claim(p_session uuid,p_offer text)
returns public.langkah_vouchers language plpgsql security definer set search_path='' as $$
declare s public.langkah_sessions; o public.langkah_offers; v public.langkah_vouchers; m public.langkah_merchants;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
 select * into s from public.langkah_sessions where id=p_session and user_id=auth.uid() for update;
 if not found then raise exception 'Mission not found'; end if;
 select * into v from public.langkah_vouchers where session_id=s.id;
 if found then return v; end if;
 if s.status<>'eligible' then raise exception 'Complete your walking goal and required checkpoints'; end if;
 if not exists(select 1 from public.langkah_routes r join public.langkah_malls mall on mall.id=r.mall_id where r.id=s.route_id and r.active and mall.geofence_reviewed) then raise exception 'This mission is paused'; end if;
 if (select count(*) from public.langkah_vouchers where user_id=auth.uid() and (issued_at at time zone 'Asia/Kuala_Lumpur')::date=(now() at time zone 'Asia/Kuala_Lumpur')::date)>=2 then raise exception 'You have reached today''s two-reward limit'; end if;
 select * into o from public.langkah_offers where id=p_offer for update;
 if not found or not o.active or o.approval<>'approved' or o.stock<1 or o.ends_at is null or o.ends_at<=now() then raise exception 'This reward is unavailable. Choose another'; end if;
 select * into m from public.langkah_merchants where id=o.merchant_id and listed;
 if not found or not exists(select 1 from public.langkah_routes where id=s.route_id and mall_id=m.mall_id) then raise exception 'Reward belongs to another mall'; end if;
 update public.langkah_offers set stock=stock-1 where id=o.id;
 insert into public.langkah_vouchers(user_id,session_id,offer_id,expires_at,title_snapshot,terms_snapshot,merchant_snapshot)
 values(auth.uid(),s.id,o.id,least(o.ends_at,now()+make_interval(days=>o.valid_days)),o.title,o.terms,m.name||' • '||m.lot) returning * into v;
 update public.langkah_sessions set status='claimed',updated_at=now() where id=s.id;
 return v;
end $$;

commit;
