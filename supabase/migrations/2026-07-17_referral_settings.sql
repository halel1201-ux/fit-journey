-- coach-controlled client referral program: on/off + coach-defined reward per friend
alter table public.coaches add column if not exists referral_enabled boolean not null default false;
alter table public.coaches add column if not exists referral_reward  text;
