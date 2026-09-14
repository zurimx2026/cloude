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
-- % del ahorro que va a fondo de emergencia (el resto va a ahorro con propósito),
-- y meta de meses de gastos fijos que el fondo de emergencia debería cubrir.
alter table profiles add column if not exists emergencia_pct_of_ahorro numeric not null default 50;
alter table profiles add column if not exists meta_emergencia_meses    numeric not null default 3;

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
-- Detalle ampliado de tarjeta (se agrega con alter para no romper instalaciones
-- que ya corrieron la versión anterior de este schema).
alter table debts add column if not exists bank          text;
alter table debts add column if not exists last4         text;
alter table debts add column if not exists limite        numeric not null default 0;
alter table debts add column if not exists corte_dia     int;
alter table debts add column if not exists pago_dia      int;
alter table debts add column if not exists pago_minimo   numeric not null default 0;

-- ---------------------------------------------------------------------------
-- Pagos registrados a una tarjeta (histórico; no son "gasto" en el
-- presupuesto, son abono a deuda — por eso viven separados de entries).
-- ---------------------------------------------------------------------------
create table if not exists card_payments (
  id          text primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  card_id     text not null,
  amount      numeric not null,
  date        date not null,
  note        text,
  created_at  timestamptz not null default now()
);
create index if not exists card_payments_user_card_idx on card_payments(user_id, card_id, date desc);

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
-- subtype: para movimientos tipo 'ahorro' -> 'emergencia' | 'proposito'.
-- meta_nombre: nombre de la meta de ahorro con propósito (ej. "viaje").
-- fuente: para movimientos tipo 'ingreso' -> nomina | freelance | apoyo_variable | renta | otro.
alter table entries add column if not exists subtype     text;
alter table entries add column if not exists meta_nombre text;
alter table entries add column if not exists fuente      text;
-- metodo_pago: null/vacío = efectivo o débito; si no, es el id de una tarjeta
-- (debts.id) — así sabemos qué tarjeta subir de saldo automáticamente.
alter table entries add column if not exists metodo_pago text;

-- ---------------------------------------------------------------------------
-- Inversiones (CETES, fondos indexados, plazo fijo, etc. — type es texto libre,
-- solo para mostrar, sin lógica especial por tipo de instrumento)
-- ---------------------------------------------------------------------------
create table if not exists investments (
  id                    text primary key,
  user_id               uuid not null references auth.users(id) on delete cascade,
  name                  text not null,
  type                  text,
  monto_inicial         numeric not null default 0,
  aportacion_mensual    numeric not null default 0,
  tasa_anual_estimada   numeric not null default 0,
  fecha_inicio          date not null default current_date
);

-- ---------------------------------------------------------------------------
-- Cierres mensuales: snapshot congelado de fin de mes, para poder comparar
-- meses futuros contra un dato fijo aunque después se editen movimientos viejos.
-- "data" guarda el snapshot completo (ingresos, gastos, ahorro, deuda,
-- inversión, patrimonio neto y el diagnóstico de texto) — un solo objeto JSON
-- en vez de una columna por campo, porque es un registro histórico de solo
-- lectura, no algo que se consulte por columna individual.
-- ---------------------------------------------------------------------------
create table if not exists monthly_summaries (
  id          text primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  month       text not null, -- 'YYYY-MM'
  data        jsonb not null,
  created_at  timestamptz not null default now(),
  unique(user_id, month)
);

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
alter table profiles          enable row level security;
alter table fixed_expenses    enable row level security;
alter table debts             enable row level security;
alter table card_payments     enable row level security;
alter table entries           enable row level security;
alter table projections       enable row level security;
alter table investments       enable row level security;
alter table monthly_summaries enable row level security;

drop policy if exists "own profile" on profiles;
create policy "own profile" on profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "own fixed_expenses" on fixed_expenses;
create policy "own fixed_expenses" on fixed_expenses
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own debts" on debts;
create policy "own debts" on debts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own card_payments" on card_payments;
create policy "own card_payments" on card_payments
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own entries" on entries;
create policy "own entries" on entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own projections" on projections;
create policy "own projections" on projections
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own investments" on investments;
create policy "own investments" on investments
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own monthly_summaries" on monthly_summaries;
create policy "own monthly_summaries" on monthly_summaries
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
