-- Panel financiero — esquema de base de datos (Supabase / Postgres)
--
-- Cómo aplicarlo: Supabase → tu proyecto → SQL Editor → pega este archivo completo → Run.
-- Es seguro volver a correrlo (usa "if not exists" / "or replace" en todo).
--
-- Modelo: una fila de datos por usuario en cada tabla, aislada con Row Level
-- Security (RLS) usando auth.uid(). Nadie puede leer o escribir datos de otro
-- usuario, ni siquiera con la anon key pública que vive en el navegador.

-- ---------------------------------------------------------------------------
-- Perfil / configuración general (1 fila por usuario)
-- ---------------------------------------------------------------------------
create table if not exists profiles (
  id                uuid primary key references auth.users(id) on delete cascade,
  ingreso_fijo      numeric not null default 6000,
  apoyo_variable    numeric not null default 0,
  alloc_ahorro      numeric not null default 12,
  alloc_estilo      numeric not null default 73,
  alloc_diversion   numeric not null default 15,
  updated_at        timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Gastos fijos (Gasolina, Gym, etc.) — el id es un slug de texto, no uuid,
-- para poder referenciarlo directo como "categoría" desde entries.
-- ---------------------------------------------------------------------------
create table if not exists fixed_expenses (
  id          text primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  icon        text not null default '💳',
  monthly     numeric not null default 0,
  sort_order  int not null default 0
);

-- ---------------------------------------------------------------------------
-- Deudas / tarjetas de crédito
-- ---------------------------------------------------------------------------
create table if not exists debts (
  id              text primary key,
  user_id         uuid not null references auth.users(id) on delete cascade,
  name            text not null,
  saldo           numeric not null default 0,
  tasa_mensual    numeric not null default 0,
  abono_mensual   numeric not null default 0
);

-- ---------------------------------------------------------------------------
-- Movimientos (gasto / ingreso / ahorro)
-- ---------------------------------------------------------------------------
create table if not exists entries (
  id          text primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  type        text not null check (type in ('gasto','ingreso','ahorro')),
  category    text,
  amount      numeric not null,
  note        text,
  date        date not null,
  created_at  timestamptz not null default now()
);
create index if not exists entries_user_date_idx on entries(user_id, date desc);

-- ---------------------------------------------------------------------------
-- Proyecciones (gastos futuros planeados)
-- ---------------------------------------------------------------------------
create table if not exists projections (
  id            text primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  description   text,
  amount        numeric not null,
  category      text,
  target_month  text not null, -- 'YYYY-MM'
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Row Level Security: cada quien ve y escribe solo sus propias filas
-- ---------------------------------------------------------------------------
alter table profiles         enable row level security;
alter table fixed_expenses   enable row level security;
alter table debts            enable row level security;
alter table entries          enable row level security;
alter table projections      enable row level security;

drop policy if exists "own profile" on profiles;
create policy "own profile" on profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "own fixed_expenses" on fixed_expenses;
create policy "own fixed_expenses" on fixed_expenses
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own debts" on debts;
create policy "own debts" on debts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own entries" on entries;
create policy "own entries" on entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own projections" on projections;
create policy "own projections" on projections
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Al crear una cuenta nueva (auth.users), crea automáticamente su fila de
-- perfil con los valores por defecto. Gastos fijos y deudas se quedan vacíos
-- hasta que el usuario guarde algo en Ajustes (el cliente ya sabe mostrar
-- valores por defecto mientras tanto).
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
