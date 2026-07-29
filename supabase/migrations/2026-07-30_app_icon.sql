-- 📱 per-coach app icon: composed icon (frame color + coach image) shown on
-- the coach's and their clients' home screens / tabs instead of the FJ icon
alter table public.coaches
  add column if not exists icon_frame_color text,
  add column if not exists app_icon_url     text;

-- raw uploaded image (before framing) so the coach can recolor the frame
-- without re-uploading, and so we never compose an already-composed icon
alter table public.coaches
  add column if not exists icon_src_url text;
