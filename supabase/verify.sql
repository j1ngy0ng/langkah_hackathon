-- Run after 001–004. Fixtures and stock changes are rolled back.
begin;
create temp table langkah_test_ids(label text primary key,id uuid default gen_random_uuid());
insert into langkah_test_ids(label) values('walker'),('other'),('merchant'),('wrong'),('admin');
insert into auth.users(id,aud,role,email,raw_user_meta_data)
select id,'authenticated','authenticated',id::text||'@example.invalid','{"role":"admin","email":"ngjingyong168@gmail.com"}'::jsonb from langkah_test_ids;
insert into public.langkah_profiles(id,role,merchant_id)
select id,case when label='admin' then 'admin' when label in ('merchant','wrong') then 'merchant' else 'resident' end,
case when label='merchant' then 'elmina-zus' when label='wrong' then 'kleast-zus' else null end from langkah_test_ids;
update public.langkah_malls set geofence_reviewed=true,qr_required=false where id in ('elmina','kl-east');
update public.langkah_routes set active=true where id in ('elmina-500','kl-east-500');
insert into public.langkah_offers(id,merchant_id,title,terms,stock,active,approval,ends_at) values
('__test_pending','elmina-zus','Test pending offer','Test terms for temporary fixtures only',5,true,'pending',now()+interval '1 day'),
('__test_live','elmina-zus','Test approved offer','Test terms for temporary fixtures only',5,true,'approved',now()+interval '1 day'),
('__test_other','kleast-zus','Test other mall offer','Test terms for temporary fixtures only',5,true,'approved',now()+interval '1 day');
create function pg_temp.expect_error(statement text,fragment text) returns void language plpgsql as $$
declare rejected boolean:=false;
begin begin execute statement; exception when others then if position(fragment in sqlerrm)=0 then raise; end if; rejected:=true; end;
if not rejected then raise exception 'Expected rejection: %',statement; end if; end $$;
create function pg_temp.as_user(label text) returns void language sql as $$
select set_config('request.jwt.claims',json_build_object('sub',id,'role','authenticated')::text,true) from langkah_test_ids where langkah_test_ids.label=$1 $$;
create function pg_temp.walk_goal(session_id uuid) returns void language plpgsql as $$
begin
-- Privileged fixture time changes are confined to this rollback test.
for i in 1..5 loop
 update public.langkah_sessions set location_checked_at=now()-interval '30 seconds' where id=session_id;
 perform public.langkah_track(session_id,i*100,3.223033,101.4370898,10,1000);
end loop;
end $$;
select pg_temp.as_user('walker');
do $$ declare s public.langkah_sessions;v public.langkah_vouchers;retry public.langkah_vouchers;
begin
if (public.langkah_profile()).role<>'resident' then raise exception 'Metadata granted a privileged role'; end if;
perform pg_temp.expect_error($q$select public.langkah_begin('elmina-500',0,0,10,1000)$q$,'boundary');
perform pg_temp.expect_error($q$select public.langkah_begin('elmina-500',3.223033,101.4370898,10,16000)$q$,'fresh');
perform pg_temp.expect_error($q$select public.langkah_start('elmina-500',3.223033,101.4370898,10)$q$,'Update');
s:=public.langkah_begin('elmina-500',3.223033,101.4370898,10,1000);
perform pg_temp.expect_error(format('select public.langkah_track(%L,1000,3.223033,101.4370898,10,1000)',s.id),'interrupted');
perform pg_temp.expect_error(format('select public.langkah_track(%L,0,0,0,10,1000)',s.id),'boundary');
perform pg_temp.expect_error(format('select public.langkah_progress(%L,500)',s.id),'fresh');
update public.langkah_sessions set location_checked_at=now()-interval '60 seconds' where id=s.id;
perform pg_temp.expect_error(format('select public.langkah_track(%L,1,3.223033,101.4370898,10,1000)',s.id),'interrupted');
perform public.langkah_track(s.id,0,3.223033,101.4370898,10,1000);
perform pg_temp.walk_goal(s.id);
perform pg_temp.expect_error(format('select public.langkah_claim(%L,%L)',s.id,'__test_pending'),'unavailable');
perform pg_temp.expect_error(format('select public.langkah_claim(%L,%L)',s.id,'__test_other'),'another mall');
v:=public.langkah_claim(s.id,'__test_live');retry:=public.langkah_claim(s.id,'__test_other');
if retry.id<>v.id or (select stock from public.langkah_offers where id='__test_live')<>4 then raise exception 'Claim retry consumed stock'; end if;
if v.terms_snapshot<>'Test terms for temporary fixtures only' or v.merchant_snapshot<>'ZUS Coffee • GF-95 & 96' then raise exception 'Voucher terms or outlet snapshot missing'; end if;
perform pg_temp.expect_error(format('select public.langkah_redeem(%L)',v.code),'another merchant');
s:=public.langkah_begin('elmina-500',3.223033,101.4370898,10,1000);perform pg_temp.walk_goal(s.id);perform public.langkah_claim(s.id,'__test_live');
s:=public.langkah_begin('elmina-500',3.223033,101.4370898,10,1000);perform pg_temp.walk_goal(s.id);
perform pg_temp.expect_error(format('select public.langkah_claim(%L,%L)',s.id,'__test_live'),'two-reward');perform public.langkah_cancel(s.id);
perform pg_temp.expect_error($q$select public.langkah_submit_offer('elmina-zus','Title','Long enough terms',2,7,now()+interval '1 day')$q$,'assigned');
perform pg_temp.expect_error($q$select public.langkah_staff_token('elmina-500','start')$q$,'Administrator');
end $$;
select pg_temp.as_user('wrong');
do $$ declare code text;begin select v.code into code from public.langkah_vouchers v where offer_id='__test_live' limit 1;perform pg_temp.expect_error(format('select public.langkah_redeem(%L)',code),'another merchant'); end $$;
select pg_temp.as_user('merchant');
do $$ declare code text;begin select v.code into code from public.langkah_vouchers v where offer_id='__test_live' limit 1;perform public.langkah_redeem(code);perform pg_temp.expect_error(format('select public.langkah_redeem(%L)',code),'already');
perform public.langkah_submit_offer('elmina-zus','New offer','Outlet-agreed terms in test only',2,7,now()+interval '1 day');
perform pg_temp.expect_error($q$select public.langkah_offer_stock('__test_pending',3,true)$q$,'approved');
end $$;
-- Staff QR: fresh, mall-specific, ordered start/finish, and no static-code bypass.
update public.langkah_malls set qr_required=true where id='elmina';
select pg_temp.as_user('admin');
select public.langkah_staff_token('elmina-500','start');select public.langkah_staff_token('elmina-500','finish');
select pg_temp.as_user('other');
do $$ declare s public.langkah_sessions;start_code text;finish_code text;
begin
perform pg_temp.expect_error($q$select public.langkah_begin('elmina-500',3.223033,101.4370898,10,1000)$q$,'start QR');
select code into start_code from public.langkah_checkin_tokens where route_id='elmina-500' and kind='start' order by expires_at desc limit 1;
select code into finish_code from public.langkah_checkin_tokens where route_id='elmina-500' and kind='finish' order by expires_at desc limit 1;
s:=public.langkah_begin('elmina-500',3.223033,101.4370898,10,1000,start_code);
perform pg_temp.expect_error(format('select public.langkah_finish_checkpoint(%L,%L,3.223033,101.4370898,10,1000)',s.id,finish_code),'step goal');
perform pg_temp.walk_goal(s.id);
if (select status from public.langkah_sessions where id=s.id)<>'walking' then raise exception 'QR was bypassed'; end if;
perform pg_temp.expect_error(format('select public.langkah_checkpoint(%L,%L)',s.id,'ELM-FINISH'),'Static');
update public.langkah_checkin_tokens set expires_at=now()-interval '1 second' where code=finish_code;
perform pg_temp.expect_error(format('select public.langkah_finish_checkpoint(%L,%L,3.223033,101.4370898,10,1000)',s.id,finish_code),'current finish');
update public.langkah_checkin_tokens set expires_at=now()+interval '30 seconds' where code=finish_code;
perform public.langkah_finish_checkpoint(s.id,finish_code,3.223033,101.4370898,10,1000);
if (select status from public.langkah_sessions where id=s.id)<>'eligible' then raise exception 'Finish QR did not unlock eligibility'; end if;
end $$;
-- Exercise actual authenticated RLS, not just security-definer business rules.
select pg_temp.as_user('other');set local role authenticated;
do $$begin
if exists(select 1 from public.langkah_vouchers where user_id<>auth.uid()) then raise exception 'Private vouchers leaked';end if;
if exists(select 1 from public.langkah_sessions where user_id<>auth.uid()) then raise exception 'Private walks leaked';end if;
if exists(select 1 from public.langkah_offers where id='__test_pending') then raise exception 'Unapproved offers leaked';end if;
if exists(select 1 from public.langkah_checkpoints) then raise exception 'Legacy checkpoints leaked';end if;
perform pg_temp.expect_error($q$update public.langkah_profiles set role='admin' where id=auth.uid()$q$,'permission denied');
perform pg_temp.expect_error($q$update public.langkah_offers set active=true where id='__test_pending'$q$,'permission denied');
perform pg_temp.expect_error($q$insert into public.langkah_reports(user_id,route_id,category,description,resolved)values(auth.uid(),'elmina-500','Other','Test forged resolution',true)$q$,'permission denied');
insert into public.langkah_reports(user_id,route_id,category,description)values(auth.uid(),'elmina-500','Other','Valid fixture feedback');
if has_table_privilege('anon','public.langkah_vouchers','select') or has_function_privilege('anon','public.langkah_claim(uuid,text)','execute') then raise exception 'Anonymous access exposed';end if;
end $$;
reset role;
rollback;
select 'PASS: fresh GPS, boundary, interval bounds, old-client bypass blocked, approved offers, mall scope, stock, retry, daily cap, redemption, expiring QR, RLS, role protection. All test data rolled back.' verification;
