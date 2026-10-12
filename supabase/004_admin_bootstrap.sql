-- The user explicitly designated this email as the initial app administrator.
-- Verification comes from auth.users, never editable profile metadata.
begin;
create or replace function public.langkah_profile() returns public.langkah_profiles language plpgsql security definer set search_path='' as $$
declare result public.langkah_profiles;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 insert into public.langkah_profiles(id,display_name)
 values(auth.uid(),left(coalesce(auth.jwt()->'user_metadata'->>'display_name','Walker'),60)) on conflict do nothing;
 if not exists(select 1 from public.langkah_profiles where role='admin') and exists(
  select 1 from auth.users where id=auth.uid() and lower(email)='ngjingyong168@gmail.com' and email_confirmed_at is not null
 ) then update public.langkah_profiles set role='admin',merchant_id=null where id=auth.uid(); end if;
 select * into result from public.langkah_profiles where id=auth.uid(); return result;
end $$;
revoke all on function public.langkah_profile() from public,anon;
grant execute on function public.langkah_profile() to authenticated;
commit;
select 'Administrator bootstrap installed; email confirmation required' status;
