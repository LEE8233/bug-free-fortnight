begin;
create table if not exists public.riz_members (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check(char_length(display_name) between 1 and 40),
 department text not null default '' check(char_length(department)<=80),
 role text not null default 'member' check(role in ('member','admin')),
 created_at timestamptz not null default now()
);
create or replace function public.riz_is_member() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.riz_members where id=auth.uid()); $$;
create or replace function public.riz_is_admin() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.riz_members where id=auth.uid() and role='admin'); $$;
revoke all on function public.riz_is_member(), public.riz_is_admin() from public;
grant execute on function public.riz_is_member(), public.riz_is_admin() to authenticated;
alter table public.riz_members enable row level security;
revoke all on public.riz_members from anon,authenticated;
grant select,insert on public.riz_members to authenticated;
grant update(display_name,department) on public.riz_members to authenticated;
drop policy if exists riz_members_read on public.riz_members;
create policy riz_members_read on public.riz_members for select to authenticated using(id=auth.uid() or public.riz_is_admin());
drop policy if exists riz_members_join on public.riz_members;
create policy riz_members_join on public.riz_members for insert to authenticated with check(id=auth.uid() and role='member');
drop policy if exists riz_members_edit on public.riz_members;
create policy riz_members_edit on public.riz_members for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create table if not exists public.riz_posts (
 id uuid primary key default gen_random_uuid(),
 board text not null check(board in ('notice','webzine','resources','gallery')),
 title text not null check(char_length(title) between 1 and 160),
 body text not null default '' check(char_length(body)<=20000),
 author_id uuid not null default auth.uid() references public.riz_members(id),
 author_name text not null check(char_length(author_name) between 1 and 40),
 file_path text, file_name text, file_mime text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 constraint riz_file_owner check(file_path is null or file_path like author_id::text || '/%'),
 constraint riz_gallery_image check(board<>'gallery' or (file_path is not null and file_mime in ('image/jpeg','image/png','image/webp','image/gif')))
);
create index if not exists riz_posts_board_date on public.riz_posts(board,created_at desc);
create or replace function public.riz_touch_post() returns trigger language plpgsql set search_path='' as $$ begin new.updated_at=now(); return new; end $$;
drop trigger if exists riz_touch_post on public.riz_posts;
create trigger riz_touch_post before update on public.riz_posts for each row execute function public.riz_touch_post();
alter table public.riz_posts enable row level security;
revoke all on public.riz_posts from anon,authenticated;
grant select,insert,delete on public.riz_posts to authenticated;
grant update(title,body) on public.riz_posts to authenticated;
drop policy if exists riz_posts_read on public.riz_posts;
create policy riz_posts_read on public.riz_posts for select to authenticated using(public.riz_is_member());
drop policy if exists riz_posts_add on public.riz_posts;
create policy riz_posts_add on public.riz_posts for insert to authenticated with check(public.riz_is_member() and author_id=auth.uid() and (board<>'notice' or public.riz_is_admin()) and author_name=(select display_name from public.riz_members where id=auth.uid()));
drop policy if exists riz_posts_edit on public.riz_posts;
create policy riz_posts_edit on public.riz_posts for update to authenticated using(public.riz_is_member() and (author_id=auth.uid() or public.riz_is_admin()) and (board<>'notice' or public.riz_is_admin())) with check(public.riz_is_member() and (author_id=auth.uid() or public.riz_is_admin()) and (board<>'notice' or public.riz_is_admin()));
drop policy if exists riz_posts_remove on public.riz_posts;
create policy riz_posts_remove on public.riz_posts for delete to authenticated using(public.riz_is_member() and (author_id=auth.uid() or public.riz_is_admin()) and (board<>'notice' or public.riz_is_admin()));
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('riz-files','riz-files',false,10485760,array['image/jpeg','image/png','image/webp','image/gif','application/pdf','text/plain','text/csv','application/zip','application/x-zip-compressed','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation']) on conflict(id) do nothing;
drop policy if exists riz_files_read on storage.objects;
create policy riz_files_read on storage.objects for select to authenticated using(bucket_id='riz-files' and public.riz_is_member());
drop policy if exists riz_files_add on storage.objects;
create policy riz_files_add on storage.objects for insert to authenticated with check(bucket_id='riz-files' and public.riz_is_member() and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists riz_files_remove on storage.objects;
create policy riz_files_remove on storage.objects for delete to authenticated using(bucket_id='riz-files' and public.riz_is_member() and ((storage.foldername(name))[1]=auth.uid()::text or public.riz_is_admin()));
commit;
-- 최초 관리자 지정: 가입·이메일 인증·리즈 회원 등록 완료 후 아래 이메일을 수정하고 별도로 실행하세요.
-- update public.riz_members set role='admin' where id=(select id from auth.users where email='관리자@회사도메인.com');
