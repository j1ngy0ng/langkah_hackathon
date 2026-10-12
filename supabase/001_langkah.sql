-- Langkah development schema. Adds only tables prefixed langkah_.
begin;

create table public.langkah_malls (
  id text primary key, name text not null, area text not null,
  latitude double precision, longitude double precision,
  radius_m integer not null default 300 check (radius_m between 50 and 2000)
);
create table public.langkah_merchants (
  id text primary key, mall_id text not null references public.langkah_malls,
  name text not null
);
create table public.langkah_profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null default 'Walker',
  role text not null default 'resident' check (role in ('resident','merchant','admin')),
  merchant_id text references public.langkah_merchants,
  check (role <> 'merchant' or merchant_id is not null)
);
create table public.langkah_routes (
  id text primary key, mall_id text not null references public.langkah_malls,
  name text not null, description text not null, target_steps integer not null check (target_steps between 100 and 20000),
  minutes integer not null check (minutes between 1 and 180),
  accessibility text not null default 'Accessibility review pending',
  active boolean not null default false
);
create table public.langkah_checkpoints (
  route_id text not null references public.langkah_routes, ordinal integer not null,
  name text not null, code text not null, primary key(route_id, ordinal),
  unique(route_id, code)
);
create table public.langkah_offers (
  id text primary key, merchant_id text not null references public.langkah_merchants,
  title text not null, terms text not null,
  stock integer not null check(stock >= 0), active boolean not null default true,
  valid_days integer not null default 7 check (valid_days between 1 and 90)
);
create table public.langkah_sessions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users on delete cascade,
  route_id text not null references public.langkah_routes,
  started_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  steps integer not null default 0 check (steps >= 0),
  checkpoint_count integer not null default 0,
  status text not null default 'walking' check (status in ('walking','eligible','claimed','cancelled')),
  latitude double precision not null, longitude double precision not null
);
create unique index langkah_one_active_session on public.langkah_sessions(user_id)
  where status in ('walking','eligible');
create table public.langkah_vouchers (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default upper(left(replace(gen_random_uuid()::text,'-',''),12)),
  user_id uuid not null references auth.users on delete cascade,
  session_id uuid not null unique references public.langkah_sessions,
  offer_id text not null references public.langkah_offers,
  issued_at timestamptz not null default now(), expires_at timestamptz not null,
  redeemed_at timestamptz, redeemed_by uuid references auth.users
);
create table public.langkah_reports (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users on delete cascade,
  route_id text not null references public.langkah_routes,
  category text not null check (category in ('Obstruction','Directions','Rest points','Accessibility','Other')),
  description text not null check (char_length(description) between 5 and 1000),
  created_at timestamptz not null default now(), resolved boolean not null default false
);

-- Staff roles come from the database, never from an app role selector.
create function public.langkah_is_admin() returns boolean language sql stable security definer
set search_path = '' as $$
  select exists(select 1 from public.langkah_profiles where id = auth.uid() and role = 'admin');
$$;
create function public.langkah_staff_merchant() returns text language sql stable security definer
set search_path = '' as $$
  select merchant_id from public.langkah_profiles where id = auth.uid() and role = 'merchant';
$$;
create function public.langkah_profile() returns public.langkah_profiles language plpgsql security definer
set search_path = '' as $$
declare result public.langkah_profiles;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  insert into public.langkah_profiles(id,display_name)
  values(auth.uid(),left(coalesce(auth.jwt()->'user_metadata'->>'display_name','Walker'),60)) on conflict do nothing;
  select * into result from public.langkah_profiles where id=auth.uid();
  return result;
end $$;

alter table public.langkah_malls enable row level security;
alter table public.langkah_merchants enable row level security;
alter table public.langkah_profiles enable row level security;
alter table public.langkah_routes enable row level security;
alter table public.langkah_checkpoints enable row level security;
alter table public.langkah_offers enable row level security;
alter table public.langkah_sessions enable row level security;
alter table public.langkah_vouchers enable row level security;
alter table public.langkah_reports enable row level security;

create policy catalog_read on public.langkah_malls for select to authenticated using(true);
create policy catalog_read on public.langkah_merchants for select to authenticated using(true);
create policy catalog_read on public.langkah_routes for select to authenticated using(true);
create policy catalog_read on public.langkah_offers for select to authenticated using(true);
create policy profile_read on public.langkah_profiles for select to authenticated using(id=auth.uid() or public.langkah_is_admin());
create policy checkpoint_admin on public.langkah_checkpoints for select to authenticated using(public.langkah_is_admin());
create policy session_read on public.langkah_sessions for select to authenticated using(user_id=auth.uid() or public.langkah_is_admin());
create policy voucher_read on public.langkah_vouchers for select to authenticated using(user_id=auth.uid() or public.langkah_is_admin() or exists(
  select 1 from public.langkah_offers o where o.id=offer_id and o.merchant_id=public.langkah_staff_merchant()));
create policy report_read on public.langkah_reports for select to authenticated using(user_id=auth.uid() or public.langkah_is_admin());
create policy report_insert on public.langkah_reports for insert to authenticated with check(user_id=auth.uid());
create policy report_resolve on public.langkah_reports for update to authenticated using(public.langkah_is_admin()) with check(public.langkah_is_admin());
create policy offer_admin on public.langkah_offers for update to authenticated using(public.langkah_is_admin()) with check(public.langkah_is_admin());
create policy route_admin on public.langkah_routes for update to authenticated using(public.langkah_is_admin()) with check(public.langkah_is_admin());

revoke all on public.langkah_malls,public.langkah_merchants,public.langkah_profiles,public.langkah_routes,
  public.langkah_checkpoints,public.langkah_offers,public.langkah_sessions,public.langkah_vouchers,public.langkah_reports from anon,authenticated;
grant select on public.langkah_malls,public.langkah_merchants,public.langkah_profiles,public.langkah_routes,
  public.langkah_offers,public.langkah_sessions,public.langkah_vouchers,public.langkah_reports to authenticated;
grant select on public.langkah_checkpoints to authenticated;
grant insert(user_id,route_id,category,description) on public.langkah_reports to authenticated;
grant update(resolved) on public.langkah_reports to authenticated;
grant update(stock,active) on public.langkah_offers to authenticated;
grant update(active) on public.langkah_routes to authenticated;
-- All session credit, issuance and redemption go through transactional functions.
revoke insert,update,delete on public.langkah_profiles,public.langkah_sessions,public.langkah_vouchers from anon,authenticated;

create function public.langkah_start(p_route text,p_lat double precision,p_lon double precision,p_accuracy double precision)
returns public.langkah_sessions language plpgsql security definer set search_path='' as $$
declare r public.langkah_routes; m public.langkah_malls; s public.langkah_sessions; metres double precision;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if p_lat is null or p_lon is null or p_accuracy is null or p_accuracy not between 0 and 75
     or p_lat not between -90 and 90 or p_lon not between -180 and 180 then raise exception 'A fresh, accurate location is required'; end if;
  select * into r from public.langkah_routes where id=p_route and active;
  if not found then raise exception 'This route awaits staff approval'; end if;
  select * into m from public.langkah_malls where id=r.mall_id;
  if m.latitude is null or m.longitude is null then raise exception 'Mall check-in location is not configured'; end if;
  metres := 6371000 * acos(least(1.0,greatest(-1.0,
    sin(radians(p_lat))*sin(radians(m.latitude)) + cos(radians(p_lat))*cos(radians(m.latitude))*cos(radians(p_lon-m.longitude)))));
  if metres > m.radius_m then raise exception 'Please check in at the selected mall'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select * into s from public.langkah_sessions where user_id=auth.uid() and status in ('walking','eligible');
  if found then
    if s.route_id<>p_route then raise exception 'Finish or cancel your current mission first'; end if;
    return s;
  end if;
  insert into public.langkah_sessions(user_id,route_id,latitude,longitude) values(auth.uid(),p_route,p_lat,p_lon) returning * into s;
  return s;
end $$;

create function public.langkah_progress(p_session uuid,p_steps integer)
returns public.langkah_sessions language plpgsql security definer set search_path='' as $$
declare s public.langkah_sessions; target integer; checkpoints integer;
begin
  select * into s from public.langkah_sessions where id=p_session and user_id=auth.uid() for update;
  if not found or s.status not in ('walking','eligible') then raise exception 'No active mission'; end if;
  if p_steps is null or p_steps<s.steps or p_steps>20000 or p_steps>extract(epoch from now()-s.started_at)*4+10 then
    raise exception 'Movement reading needs review'; end if;
  select target_steps into target from public.langkah_routes where id=s.route_id;
  select count(*) into checkpoints from public.langkah_checkpoints where route_id=s.route_id;
  update public.langkah_sessions set steps=p_steps,updated_at=now(),
    status=case when p_steps>=target and s.checkpoint_count>=checkpoints then 'eligible' else 'walking' end
    where id=s.id returning * into s;
  return s;
end $$;

create function public.langkah_checkpoint(p_session uuid,p_code text)
returns public.langkah_sessions language plpgsql security definer set search_path='' as $$
declare s public.langkah_sessions; required_code text; target integer; total integer;
begin
  select * into s from public.langkah_sessions where id=p_session and user_id=auth.uid() for update;
  if not found or s.status not in ('walking','eligible') then raise exception 'No active mission'; end if;
  select code into required_code from public.langkah_checkpoints where route_id=s.route_id and ordinal=s.checkpoint_count+1;
  if required_code is null or upper(trim(p_code))<>required_code then raise exception 'Checkpoint code is not valid for the next stop'; end if;
  select target_steps into target from public.langkah_routes where id=s.route_id;
  select count(*) into total from public.langkah_checkpoints where route_id=s.route_id;
  update public.langkah_sessions set checkpoint_count=checkpoint_count+1,updated_at=now(),
    status=case when s.steps>=target and s.checkpoint_count+1>=total then 'eligible' else 'walking' end
    where id=s.id returning * into s;
  return s;
end $$;

create function public.langkah_cancel(p_session uuid) returns void language sql security definer set search_path='' as $$
  update public.langkah_sessions set status='cancelled',updated_at=now() where id=p_session and user_id=auth.uid() and status in ('walking','eligible');
$$;

create function public.langkah_claim(p_session uuid,p_offer text)
returns public.langkah_vouchers language plpgsql security definer set search_path='' as $$
declare s public.langkah_sessions; o public.langkah_offers; v public.langkah_vouchers; daily integer;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
  select * into s from public.langkah_sessions where id=p_session and user_id=auth.uid() for update;
  if not found then raise exception 'Mission not found'; end if;
  select * into v from public.langkah_vouchers where session_id=s.id;
  if found then return v; end if; -- retry returns the existing voucher
  if s.status<>'eligible' then raise exception 'Complete your movement goal and checkpoints first'; end if;
  if not exists(select 1 from public.langkah_routes where id=s.route_id and active) then raise exception 'This route is paused'; end if;
  select count(*) into daily from public.langkah_vouchers where user_id=auth.uid()
    and (issued_at at time zone 'Asia/Kuala_Lumpur')::date=(now() at time zone 'Asia/Kuala_Lumpur')::date;
  if daily>=2 then raise exception 'You have reached today''s two-reward limit'; end if;
  select * into o from public.langkah_offers where id=p_offer for update;
  if not found or not o.active or o.stock<1 then raise exception 'This reward is unavailable. Choose another'; end if;
  if not exists(select 1 from public.langkah_routes r join public.langkah_merchants m on m.mall_id=r.mall_id
    where r.id=s.route_id and m.id=o.merchant_id) then raise exception 'Reward belongs to another mall'; end if;
  update public.langkah_offers set stock=stock-1 where id=o.id;
  insert into public.langkah_vouchers(user_id,session_id,offer_id,expires_at)
    values(auth.uid(),s.id,o.id,now()+make_interval(days=>o.valid_days)) returning * into v;
  update public.langkah_sessions set status='claimed',updated_at=now() where id=s.id;
  return v;
end $$;

create function public.langkah_redeem(p_code text)
returns public.langkah_vouchers language plpgsql security definer set search_path='' as $$
declare v public.langkah_vouchers; merchant text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  select * into v from public.langkah_vouchers where code=upper(trim(p_code)) for update;
  if not found then raise exception 'Voucher not found'; end if;
  select merchant_id into merchant from public.langkah_offers where id=v.offer_id;
  if not public.langkah_is_admin() and merchant is distinct from public.langkah_staff_merchant() then raise exception 'This voucher belongs to another merchant'; end if;
  if v.redeemed_at is not null then raise exception 'Voucher has already been redeemed'; end if;
  if v.expires_at<=now() then raise exception 'Voucher has expired'; end if;
  update public.langkah_vouchers set redeemed_at=now(),redeemed_by=auth.uid() where id=v.id returning * into v;
  return v;
end $$;

-- Revoke default public execution on every Langkah RPC.
do $$ declare fn record; begin
  for fn in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'langkah_%'
  loop execute format('revoke all on function %s from public, anon',fn.signature);
       execute format('grant execute on function %s to authenticated',fn.signature); end loop;
end $$;

insert into public.langkah_malls values ('elmina','Elmina Lakeside Mall','City of Elmina',3.223033,101.4370898,300);
insert into public.langkah_merchants values
 ('cafe','elmina','Sample Corner Café'),('active','elmina','Sample Active Store'),('books','elmina','Sample Bookshop');
insert into public.langkah_routes values
 ('mall-loop','elmina','The easy mall loop','A short introductory mission. Staff must check the physical route before opening it.',500,10,'Accessibility review pending',false),
 ('lakeside-loop','elmina','The lakeside discovery','A longer mission template. Outdoor access and conditions need a site review.',1000,20,'Accessibility review pending',false);
insert into public.langkah_checkpoints values
 ('mall-loop',1,'Start checkpoint','ELM-START'),('mall-loop',2,'Finish checkpoint','ELM-FINISH'),
 ('lakeside-loop',1,'Start checkpoint','LAKE-START'),('lakeside-loop',2,'Finish checkpoint','LAKE-FINISH');
insert into public.langkah_offers(id,merchant_id,title,terms,stock) values
 ('coffee','cafe','RM3 off a drink','Sample offer only. One voucher per transaction. No merchant partnership confirmed.',40),
 ('active','active','10% off an accessory','Sample offer only. Discount capped at RM10. No merchant partnership confirmed.',30),
 ('books','books','RM5 off a book','Sample offer only. Minimum spend RM30. No merchant partnership confirmed.',30);

commit;
