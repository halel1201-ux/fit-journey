-- training-cycle week counter: coach resets on deload; week N = weeks since this date
alter table public.clients
  add column if not exists training_cycle_start date;
