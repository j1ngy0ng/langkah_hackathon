-- Upgrade existing installation without deleting accounts, walks or vouchers.
begin;
alter table public.langkah_malls add column source_url text;
alter table public.langkah_malls add column address text;
alter table public.langkah_malls add column verified_at date;
alter table public.langkah_malls add column geofence_reviewed boolean not null default false;
alter table public.langkah_malls add column qr_required boolean not null default false;
alter table public.langkah_merchants add column lot text;
alter table public.langkah_merchants add column source_url text;
alter table public.langkah_merchants add column verified_at date;
alter table public.langkah_merchants add column listed boolean not null default false;
alter table public.langkah_offers add column approval text not null default 'pending' check(approval in ('pending','approved','rejected'));
alter table public.langkah_offers add column approval_reference text;
alter table public.langkah_offers add column approved_by uuid references auth.users;
alter table public.langkah_offers add column approved_at timestamptz;
alter table public.langkah_offers add column ends_at timestamptz;
alter table public.langkah_sessions add column location_checked_at timestamptz;
alter table public.langkah_sessions add column qr_required boolean not null default false;
alter table public.langkah_vouchers add column title_snapshot text;
alter table public.langkah_vouchers add column terms_snapshot text;
alter table public.langkah_vouchers add column merchant_snapshot text;
update public.langkah_offers set active=false where id in ('coffee','active','books');
update public.langkah_routes set active=false where id in ('mall-loop','lakeside-loop');

-- Facts selected from official directories, checked 2026-10-11. Map pins are
-- initial centres, NOT surveyed mall boundaries. Staff must review geofences.
update public.langkah_malls set address='No. 5, Persiaran Garcinia, Elmina West, 40170 Shah Alam',
 source_url='https://www.simedarbyproperty.com/malls/elmina-lake-side-mall/',verified_at='2026-10-11',radius_m=200 where id='elmina';
insert into public.langkah_malls(id,name,area,latitude,longitude,radius_m,address,source_url,verified_at) values
 ('kl-east','KL East Mall','KL East, Kuala Lumpur',3.2247781,101.7304658,150,'823, Jalan Lingkaran Tengah 2, KL Timur, 53100 Kuala Lumpur','https://www.simedarbyproperty.com/malls/kleast-mall/','2026-10-11'),
 ('klgcc','KLGCC Mall','Bukit Kiara, Kuala Lumpur',3.1376273,101.6485627,150,'Jalan Bukit Kiara 1, Bukit Kiara, 60000 Kuala Lumpur','https://www.simedarbyproperty.com/malls/klgcc-mall/','2026-10-11');
insert into public.langkah_merchants(id,mall_id,name,lot,listed) values
 ('elmina-zus','elmina','ZUS Coffee','GF-95 & 96',true),
 ('elmina-scoop','elmina','Inside Scoop','GF-13A',true),
 ('elmina-decathlon','elmina','Decathlon','GF-97',true),
 ('kleast-zus','kl-east','ZUS Coffee','G2K-03A',true),
 ('kleast-scoop','kl-east','Inside Scoop','G1K-01',true),
 ('kleast-decathlon','kl-east','Decathlon','G2-17, G2-17A, G2-18, G2-19 & G2-20',true),
 ('klgcc-huckleberry','klgcc','Huckleberry','GF-13',true),
 ('klgcc-matcha','klgcc','Oh Cha Matcha','GFK-03',true),
 ('klgcc-jaya','klgcc','Jaya Grocer','GF-07',true);
update public.langkah_merchants s set source_url=m.source_url,verified_at=m.verified_at
 from public.langkah_malls m where m.id=s.mall_id and s.listed;
insert into public.langkah_routes(id,mall_id,name,description,target_steps,minutes,accessibility,active)
 select m.id||'-500',m.id,'A little mall walk','Walk in the public mall areas at your own pace. Keep clear of shop entrances and rest whenever needed.',500,10,'Use public walkways. Ask mall staff about step-free access and rest points.',false from public.langkah_malls m;
insert into public.langkah_routes(id,mall_id,name,description,target_steps,minutes,accessibility,active)
 select m.id||'-1000',m.id,'Make time to move','Build a longer walking visit in the public mall areas. No fixed route or medical fitness claim.',1000,20,'Use public walkways. Ask mall staff about step-free access and rest points.',false from public.langkah_malls m;

create table public.langkah_merchant_requests(
 user_id uuid primary key references auth.users on delete cascade,
 merchant_id text not null references public.langkah_merchants,
 contact text not null check(char_length(contact) between 5 and 300),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 requested_at timestamptz not null default now(),reviewed_at timestamptz,reviewed_by uuid references auth.users
);
alter table public.langkah_merchant_requests enable row level security;
create policy request_read on public.langkah_merchant_requests for select to authenticated using(user_id=auth.uid() or public.langkah_is_admin());
revoke all on public.langkah_merchant_requests from public,anon,authenticated;
grant select on public.langkah_merchant_requests to authenticated;
create table public.langkah_checkin_tokens(
 code text primary key default upper(replace(gen_random_uuid()::text,'-','')),
 route_id text not null references public.langkah_routes,kind text not null check(kind in ('start','finish')),
 expires_at timestamptz not null default(now()+interval '60 seconds'),created_by uuid not null references auth.users
);
alter table public.langkah_checkin_tokens enable row level security;
revoke all on public.langkah_checkin_tokens from public,anon,authenticated;

-- Do not let older clients bypass new location and offer approval checks.
create or replace function public.langkah_start(p_route text,p_lat double precision,p_lon double precision,p_accuracy double precision)
returns public.langkah_sessions language plpgsql security definer set search_path='' as $$
begin raise exception 'Update Langkah to use verified walking'; end $$;
create or replace function public.langkah_progress(p_session uuid,p_steps integer)
returns public.langkah_sessions language plpgsql security definer set search_path='' as $$
begin raise exception 'Update Langkah: every progress update needs a fresh location'; end $$;
create or replace function public.langkah_checkpoint(p_session uuid,p_code text)
returns public.langkah_sessions language plpgsql security definer set search_path='' as $$
begin raise exception 'Static checkpoint codes are no longer accepted'; end $$;

create function public.langkah_validate_location(p_mall text,p_lat double precision,p_lon double precision,p_accuracy double precision,p_age_ms bigint)
returns void language plpgsql security definer set search_path='' as $$
declare m public.langkah_malls; d double precision;
begin
 select * into m from public.langkah_malls where id=p_mall;
 if not found or not m.geofence_reviewed then raise exception 'Mall location boundary awaits administrator review'; end if;
 if p_lat is null or p_lon is null or p_accuracy is null or p_age_ms is null
  or p_lat not between -90 and 90 or p_lon not between -180 and 180
  or p_accuracy not between 0 and 75 or p_age_ms not between 0 and 15000 then raise exception 'A fresh location accurate to 75 metres or better is required'; end if;
 d:=6371000*acos(least(1.0,greatest(-1.0,sin(radians(p_lat))*sin(radians(m.latitude))+cos(radians(p_lat))*cos(radians(m.latitude))*cos(radians(p_lon-m.longitude)))));
 if d+p_accuracy>m.radius_m then raise exception 'Location is outside or too close to the mall boundary. Move further inside and try again'; end if;
end $$;

create function public.langkah_begin(p_route text,p_lat double precision,p_lon double precision,p_accuracy double precision,p_age_ms bigint,p_code text default null)
returns public.langkah_sessions language plpgsql security definer set search_path='' as $$
declare r public.langkah_routes; m public.langkah_malls; s public.langkah_sessions;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 select * into r from public.langkah_routes where id=p_route and active;
 if not found then raise exception 'This mission is not open yet'; end if;
 select * into m from public.langkah_malls where id=r.mall_id;
 perform public.langkah_validate_location(m.id,p_lat,p_lon,p_accuracy,p_age_ms);
 perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
 select * into s from public.langkah_sessions where user_id=auth.uid() and status in ('walking','eligible');
 if found then
  if s.route_id<>p_route then raise exception 'Finish or cancel your current mission first'; end if;
  return s;
 end if;
 if m.qr_required and not exists(select 1 from public.langkah_checkin_tokens where code=upper(trim(p_code)) and route_id=r.id and kind='start' and expires_at>now()) then raise exception 'Scan the current staff start QR at this mall'; end if;
 insert into public.langkah_sessions(user_id,route_id,latitude,longitude,location_checked_at,qr_required,checkpoint_count)
 values(auth.uid(),r.id,p_lat,p_lon,now(),m.qr_required,case when m.qr_required then 1 else 0 end) returning * into s;
 return s;
end $$;

create function public.langkah_track(p_session uuid,p_steps integer,p_lat double precision,p_lon double precision,p_accuracy double precision,p_age_ms bigint)
returns public.langkah_sessions language plpgsql security definer set search_path='' as $$
declare s public.langkah_sessions; r public.langkah_routes; elapsed double precision;
begin
 select * into s from public.langkah_sessions where id=p_session and user_id=auth.uid() for update;
 if not found or s.status not in ('walking','eligible') then raise exception 'No active mission'; end if;
 select * into r from public.langkah_routes where id=s.route_id and active;
 if not found then raise exception 'This mission has been paused by staff'; end if;
 perform public.langkah_validate_location(r.mall_id,p_lat,p_lon,p_accuracy,p_age_ms);
 elapsed:=extract(epoch from now()-coalesce(s.location_checked_at,s.started_at));
 if p_steps is null or p_steps<s.steps or p_steps>20000 or (p_steps>s.steps and (elapsed>45 or p_steps-s.steps>least(elapsed,45)*4+10)) then raise exception 'Walking verification was interrupted. Resume tracking to start a fresh interval'; end if;
 update public.langkah_sessions set steps=p_steps,latitude=p_lat,longitude=p_lon,location_checked_at=now(),updated_at=now(),
 status=case when p_steps>=r.target_steps and (not s.qr_required or s.checkpoint_count>=2) then 'eligible' else 'walking' end
 where id=s.id returning * into s;
 return s;
end $$;

create function public.langkah_finish_checkpoint(p_session uuid,p_code text,p_lat double precision,p_lon double precision,p_accuracy double precision,p_age_ms bigint)
returns public.langkah_sessions language plpgsql security definer set search_path='' as $$
declare s public.langkah_sessions; r public.langkah_routes;
begin
 select * into s from public.langkah_sessions where id=p_session and user_id=auth.uid() for update;
 if not found or not s.qr_required or s.status<>'walking' or s.checkpoint_count<>1 then raise exception 'No pending finish checkpoint'; end if;
 select * into r from public.langkah_routes where id=s.route_id and active;
 if not found or s.steps<r.target_steps then raise exception 'Complete your step goal before the finish checkpoint'; end if;
 perform public.langkah_validate_location(r.mall_id,p_lat,p_lon,p_accuracy,p_age_ms);
 if not exists(select 1 from public.langkah_checkin_tokens where code=upper(trim(p_code)) and route_id=r.id and kind='finish' and expires_at>now()) then raise exception 'Scan the current finish QR for this mission'; end if;
 update public.langkah_sessions set checkpoint_count=2,status='eligible',location_checked_at=now(),updated_at=now() where id=s.id returning * into s;
 return s;
end $$;

create function public.langkah_staff_token(p_route text,p_kind text) returns public.langkah_checkin_tokens language plpgsql security definer set search_path='' as $$
declare t public.langkah_checkin_tokens;
begin
 if not public.langkah_is_admin() then raise exception 'Administrator access required'; end if;
 if not exists(select 1 from public.langkah_routes where id=p_route and active) or p_kind not in ('start','finish') then raise exception 'Choose an open mission and checkpoint'; end if;
 delete from public.langkah_checkin_tokens where expires_at<now()-interval '1 hour';
 select * into t from public.langkah_checkin_tokens where route_id=p_route and kind=p_kind and expires_at>now()+interval '5 seconds' order by expires_at desc limit 1;
 if not found then insert into public.langkah_checkin_tokens(route_id,kind,created_by) values(p_route,p_kind,auth.uid()) returning * into t; end if;
 return t;
end $$;

create function public.langkah_request_merchant(p_merchant text,p_contact text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if not exists(select 1 from public.langkah_merchants where id=p_merchant and listed) then raise exception 'Choose a listed shop'; end if;
 if exists(select 1 from public.langkah_profiles where id=auth.uid() and role<>'resident') then raise exception 'This account already has staff access'; end if;
 insert into public.langkah_merchant_requests(user_id,merchant_id,contact) values(auth.uid(),p_merchant,trim(p_contact))
 on conflict(user_id) do update set merchant_id=excluded.merchant_id,contact=excluded.contact,status='pending',requested_at=now(),reviewed_at=null,reviewed_by=null;
end $$;
create function public.langkah_review_merchant(p_user uuid,p_approve boolean) returns void language plpgsql security definer set search_path='' as $$
declare q public.langkah_merchant_requests;
begin
 if not public.langkah_is_admin() then raise exception 'Administrator access required'; end if;
 select * into q from public.langkah_merchant_requests where user_id=p_user and status='pending' for update;
 if not found then raise exception 'No pending request'; end if;
 if p_approve then update public.langkah_profiles set role='merchant',merchant_id=q.merchant_id where id=q.user_id and role='resident';
  if not found then raise exception 'Account is not an unassigned resident'; end if;
 end if;
 update public.langkah_merchant_requests set status=case when p_approve then 'approved' else 'rejected' end,reviewed_at=now(),reviewed_by=auth.uid() where user_id=p_user;
end $$;
create function public.langkah_submit_offer(p_merchant text,p_title text,p_terms text,p_stock integer,p_days integer,p_ends timestamptz) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.langkah_is_admin() and p_merchant is distinct from public.langkah_staff_merchant() then raise exception 'This shop is not assigned to you'; end if;
 if not exists(select 1 from public.langkah_merchants where id=p_merchant and listed) or char_length(trim(p_title)) not between 3 and 100 or char_length(trim(p_terms)) not between 10 and 2000 or p_stock not between 1 and 1000000 or p_days not between 1 and 90 or p_ends is null or p_ends<=now() or p_ends>now()+interval '366 days' then raise exception 'Check offer title, terms, quantity, validity and campaign end date'; end if;
 insert into public.langkah_offers(id,merchant_id,title,terms,stock,active,valid_days,ends_at) values(gen_random_uuid()::text,p_merchant,trim(p_title),trim(p_terms),p_stock,false,p_days,p_ends);
end $$;
create function public.langkah_approve_offer(p_offer text,p_approve boolean,p_reference text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.langkah_is_admin() then raise exception 'Administrator access required'; end if;
 if p_approve and (p_reference is null or char_length(trim(p_reference)) not between 5 and 300) then raise exception 'Record the merchant approval reference before publishing'; end if;
 update public.langkah_offers set approval=case when p_approve then 'approved' else 'rejected' end,active=p_approve,approval_reference=trim(p_reference),approved_by=auth.uid(),approved_at=now() where id=p_offer and approval='pending' and ends_at>now();
 if not found then raise exception 'No current pending offer'; end if;
end $$;
create function public.langkah_offer_stock(p_offer text,p_stock integer,p_active boolean) returns void language plpgsql security definer set search_path='' as $$
declare o public.langkah_offers;
begin
 select * into o from public.langkah_offers where id=p_offer for update;
 if not found or (not public.langkah_is_admin() and o.merchant_id is distinct from public.langkah_staff_merchant()) then raise exception 'No permission for this offer'; end if;
 if p_stock is null or p_stock not between 0 and 1000000 then raise exception 'Enter stock between 0 and 1000000'; end if;
 if p_active and (o.approval<>'approved' or o.ends_at is null or o.ends_at<=now()) then raise exception 'Only approved, current offers can open'; end if;
 update public.langkah_offers set stock=p_stock,active=p_active where id=o.id;
end $$;
revoke update on public.langkah_offers from authenticated;
revoke update(stock,active) on public.langkah_offers from authenticated;
drop policy catalog_read on public.langkah_offers;
create policy offer_read on public.langkah_offers for select to authenticated using(
 approval='approved' or public.langkah_is_admin() or merchant_id=public.langkah_staff_merchant()
 or exists(select 1 from public.langkah_vouchers v where v.offer_id=langkah_offers.id and v.user_id=auth.uid()));
-- Avoid a policy cycle through voucher_read -> offers -> vouchers.
drop policy voucher_read on public.langkah_vouchers;
create function public.langkah_offer_merchant(p_offer text) returns text language sql stable security definer set search_path='' as $$ select merchant_id from public.langkah_offers where id=p_offer $$;
create policy voucher_read on public.langkah_vouchers for select to authenticated using(user_id=auth.uid() or public.langkah_is_admin() or public.langkah_offer_merchant(offer_id)=public.langkah_staff_merchant());

create function public.langkah_configure_mall(p_mall text,p_lat double precision,p_lon double precision,p_radius integer,p_reviewed boolean,p_qr boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.langkah_is_admin() then raise exception 'Administrator access required'; end if;
 if p_lat is null or p_lon is null or p_radius is null or p_reviewed is null or p_qr is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 or p_radius not between 50 and 500 then raise exception 'Check coordinates and radius (50–500 metres)'; end if;
 update public.langkah_malls set latitude=p_lat,longitude=p_lon,radius_m=p_radius,geofence_reviewed=p_reviewed,qr_required=p_qr where id=p_mall;
 if not found then raise exception 'Mall not found'; end if;
 if not p_reviewed then update public.langkah_routes set active=false where mall_id=p_mall; end if;
end $$;

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

do $$ declare f record; begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'langkah_%' loop
  execute format('revoke all on function %s from public,anon',f.signature);
  execute format('grant execute on function %s to authenticated',f.signature);
 end loop;
end $$;
revoke all on function public.langkah_validate_location(text,double precision,double precision,double precision,bigint) from authenticated;

-- Assign only the explicitly identified, email-confirmed existing account.
insert into public.langkah_profiles(id,display_name,role)
 select id,coalesce(raw_user_meta_data->>'display_name','Administrator'),'admin' from auth.users
 where lower(email)='ngjingyong168@gmail.com' and email_confirmed_at is not null
on conflict(id) do update set role='admin',merchant_id=null;
commit;
select 'Installed' status,(select count(*) from public.langkah_malls) malls,(select count(*) from public.langkah_merchants where listed) listed_shops,
 exists(select 1 from public.langkah_profiles p join auth.users u on u.id=p.id where lower(u.email)='ngjingyong168@gmail.com' and p.role='admin') administrator_ready;
