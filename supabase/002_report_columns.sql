-- Applied after the initial schema to constrain report creation fields.
begin;
revoke insert on public.langkah_reports from authenticated;
grant insert(user_id,route_id,category,description) on public.langkah_reports to authenticated;
commit;
