# Panel — Finanzas personales

App de finanzas personales: registro diario, alertas, proyecciones de gastos futuros,
control de tarjetas de crédito, y un bot integrado que responde con Claude usando tu
contexto financiero actual.

**Supabase (login + base de datos en la nube) es opcional.** Sin configurarlo, la app
funciona sola con localStorage — sin pedir cuenta, lista para usarse en cuanto la subes a
Netlify. Si más adelante configuras `public/config.js` (ver más abajo), se activa el login
y tus datos empiezan a sincronizar entre dispositivos. Puedes empezar sin Supabase y
agregarlo después sin perder nada — la primera vez que inicies sesión, la app detecta lo
que ya tenías guardado en el navegador y te ofrece importarlo a tu cuenta nueva.

## Estructura

```
public/index.html            App (una sola página, sin build). Funciona en modo local
                              (localStorage) si no hay config.js; con Supabase configurado,
                              pide login y todo vive en Postgres, sincronizado entre
                              dispositivos.
public/config.example.js     Plantilla de config.js (URL + anon key de tu proyecto Supabase).
netlify/functions/ask-bot.js Función serverless: llama a la API de Claude con tu API key
                              guardada en el servidor, y valida que quien pregunta tenga
                              sesión real. El navegador nunca ve la API key.
netlify.toml                  Config de Netlify (publish dir + functions dir).
supabase/schema.sql           Esquema de base de datos (tablas + Row Level Security).
```

## Módulos

- **Proyectar** (incluye Proyecciones + Inversión en la misma pestaña):
  - **Proyecciones**: apartas un gasto futuro (qué, cuánto, para cuándo) y la app te da un
    semáforo (✓/⚠/✗) evaluando tu presupuesto de Diversión/Libre restante, tu avance de
    ahorro del mes y si tienes deuda generando interés. La lógica vive en
    `evaluateProjection()` dentro de `public/index.html` — es una heurística transparente,
    no una llamada a IA, así que siempre puedes ver los números detrás de la recomendación.
  - **Inversión**: control de inversiones (CETES, fondos indexados, plazo fijo, etc. — el
    tipo es texto libre, solo para mostrar). Por inversión: monto inicial, aportación
    mensual, tasa anual estimada y fecha de inicio. Proyecta el valor estimado a 12/24/60
    meses con interés compuesto simple (`estimateInvestmentValue()`) — no considera
    comisiones ni impuestos, es una estimación para orientar, no un cálculo contable.
  - **Pregúntale a Claude**: un cuadro de chat que manda tu pregunta + un resumen de tu
    situación financiera actual (`buildFinancialContext()`, que ya incluye lo de arriba) a
    la función `ask-bot`, que la reenvía a la API de Claude.
- **Tarjetas**: pestaña dedicada al control de tus tarjetas de crédito. Por cada tarjeta:
  banco, últimos 4 dígitos, saldo, límite (con barra de % de uso), tasa mensual, abono
  mensual comprometido, día de corte y de pago, y pago mínimo. Incluye:
  - **Resumen global**: deuda total, interés estimado del mes, abono total comprometido,
    % de uso de crédito (solo entre las tarjetas con límite cargado), y qué tarjeta
    conviene priorizar si tienes dinero extra (la de tasa más alta — método "avalancha").
  - **Reporte automático por ciclo**: al registrar un gasto puedes elegir "Método de
    pago" — Efectivo/Débito o una de tus tarjetas. Si eliges una tarjeta, el saldo de esa
    tarjeta sube solo con el gasto (y baja si lo borras), y cada tarjeta muestra cuánto
    llevas gastado en el ciclo actual (de corte a corte — `cardCycleRange()`; si no
    configuraste el día de corte, usa el mes calendario de respaldo), con el detalle de
    cada gasto. Así el saldo mostrado siempre es lo que realmente te toca pagar, sin
    tener que sumarlo a mano.
  - **Simulador de liquidación** (`simulatePayoff()`): con el saldo, tasa y abono actuales
    de cada tarjeta, calcula en cuántos meses llegas a $0 y cuánto interés vas a pagar en
    el camino — o te avisa si tu abono actual ni siquiera cubre el interés mensual, caso
    en el que nunca bajaría el saldo.
  - **Registrar pago**: descuenta el pago del saldo al instante y lo guarda en un
    historial por tarjeta (tabla `card_payments`, separada de `entries` porque un pago a
    tarjeta no es "gasto" en el presupuesto — es mover dinero ya presupuestado a deuda).
  - **Alertas** en la pestaña Hoy: tarjeta cerca de su límite, pago que vence en los
    próximos días, y abono que no alcanza a cubrir el interés del mes.
  - El bot y el módulo de Proyecciones ya usan estos datos (utilización, simulación de
    liquidación) como parte de tu contexto financiero.
  - **"¿Y si pago extra?"**: calculadora de abono hipotético — pon un extra mensual y
    compara contra tu abono actual cuántos meses y cuánto interés te ahorrarías.
- **Importar desde Excel**: en Historial, sube un `.xlsx`/`.xls`/`.csv` (por ejemplo el
  mismo CSV que exportas desde ahí) y la app llena tus movimientos sola. Detecta columnas
  de forma flexible — Fecha, Tipo, Categoría, Método de pago, Monto, Nota, Fuente — sin
  importar el orden ni mayúsculas/minúsculas (`parseImportedRows()`). Antes de guardar
  nada te muestra una vista previa con cuántos movimientos va a importar y cuántas filas
  no pudo leer, para que confirmes. Si un gasto trae método de pago con el nombre de una
  tarjeta, esa tarjeta sube de saldo automático igual que al capturar a mano. No detecta
  duplicados — usa el archivo del mismo periodo una sola vez.
- **Ahorro: emergencia vs propósito**: los movimientos de ahorro ahora piden si son para tu
  fondo de emergencia o para una meta con nombre (viaje, enganche, etc.). En Ajustes defines
  qué % de tu ahorro total va a cada uno. En Hoy se ven como dos barras separadas, y la de
  emergencia además muestra a cuántos meses de tus gastos fijos equivale lo acumulado — esa
  es la métrica que de verdad importa para un fondo de emergencia, no solo el monto en pesos.
- **Ingresos**: los movimientos de ingreso ahora piden una fuente (Nómina, Freelance, Apoyo
  variable, Renta, Otro). En Historial hay una sección que compara tu ingreso real del mes
  contra lo configurado (fijo + apoyo variable), el desglose por fuente, y una gráfica de
  barras de los últimos 6 meses para detectar meses flacos.
- **Patrimonio neto**: en la parte de arriba de Hoy, `ahorro acumulado + valor estimado de
  inversiones − deuda total`, con su desglose. Es el indicador más importante de toda la
  app — todo lo demás (presupuesto, deuda, ahorro, inversión) alimenta este número.
- **Cierres mensuales**: en Historial, un botón "Cerrar [mes]" congela un snapshot del mes
  que acaba de terminar (ingresos, gastos por categoría, ahorro, interés pagado, deuda,
  inversión y patrimonio neto) junto con un diagnóstico automático en texto (categoría que
  más se salió de presupuesto, Diversión vs. tu promedio de los últimos 3 meses cerrados,
  si algún abono no cubrió el interés generado, y si tu patrimonio neto subió o bajó y por
  qué). Es un snapshot congelado a propósito — no se recalcula después — para poder comparar
  meses futuros contra un dato fijo aunque edites movimientos viejos. Si ya pasó el día 1
  del mes y no cerraste el anterior, te avisa en Alertas.
- **Cuenta** (opcional): si configuras Supabase, se activa login con correo y contraseña.
  Tus datos (config, gastos fijos, tarjetas, pagos, movimientos, proyecciones) se guardan
  en Postgres, aislados por usuario con Row Level Security — sincronizan solos entre tu
  teléfono y cualquier otro dispositivo donde inicies sesión. Si la app detecta datos ya
  guardados en el navegador (de cuando corría en modo local), te ofrece importarlos a tu
  cuenta la primera vez que inicias sesión. Sin Supabase configurado, la app simplemente
  no pide cuenta y todo vive en el navegador — ver "Puesta en marcha" abajo.

## Puesta en marcha

### Opción rápida: desplegar ya, sin Supabase

Si solo quieres que la app funcione en Netlify hoy (guardando todo en el navegador, sin
login), sáltate directo a **"2. Desplegar en Netlify"** y omite todo lo de `config.js` —
sin ese archivo, la app arranca en modo local automáticamente. Puedes agregar Supabase
cuando quieras después, sin perder tus datos (te los ofrece importar al crear tu cuenta).

### 1. Crear el proyecto de Supabase (opcional — activa login + sincronización en la nube)

1. Crea una cuenta gratis en [supabase.com](https://supabase.com) y un proyecto nuevo.
2. Ve a **SQL Editor** → pega el contenido completo de `supabase/schema.sql` → *Run*.
   Esto crea las tablas, activa Row Level Security, y un trigger que le crea su fila de
   perfil a cada cuenta nueva automáticamente. Si ya lo habías corrido antes (de una
   versión sin Tarjetas, Inversión o Cierres mensuales), vuelve a correr el archivo
   completo — usa `alter table ... add column if not exists` y `create table if not
   exists`, así que es seguro repetirlo y solo agrega lo que falte.
3. Ve a **Project Settings → API** y copia dos valores:
   - **Project URL**
   - **anon public key**
4. En `public/`, copia `config.example.js` a `config.js` y pon esos dos valores ahí. Es
   seguro que la anon key viva en el navegador — la protección real es el Row Level
   Security del paso 2, no que la key sea secreta.
5. Opcional pero recomendado mientras seas el único usuario: en **Authentication →
   Providers → Email**, puedes desactivar "Confirm email" para no tener que confirmar tu
   correo cada vez que pruebes una cuenta nueva.

### 2. Desplegar en Netlify

1. Netlify → *Add new site* → *Import an existing project* → selecciona este repo.
   Build command: vacío. Publish directory: `public`. (`netlify.toml` ya define todo lo
   demás, incluyendo `netlify/functions`.)
2. Sin hacer nada más, dale **Deploy**. Sin `public/config.js` en el repo, la app arranca
   en modo local (sin pedir cuenta) — ya está lista para usarse.
3. **Solo si quieres activar Supabase** (login + sincronización): `public/config.js` está
   en `.gitignore` porque cada quien pone ahí los valores de su propio proyecto — pero
   como es un sitio conectado a git (deploy continuo), Netlify solo sirve lo que esté en
   el repo. La forma más simple: quita esa línea de `.gitignore` y haz commit de tu
   `config.js` real — no pasa nada porque la anon key es segura para ser pública (la
   protección de verdad es el Row Level Security del paso 1). Si prefieres no tenerlo en
   git, la alternativa es agregar un build command en Netlify que lo genere en cada
   deploy a partir de variables de entorno (`echo "window.SUPABASE_URL='$SUPABASE_URL';
   window.SUPABASE_ANON_KEY='$SUPABASE_ANON_KEY';" > public/config.js`), configurando
   esas dos variables en Netlify.
4. **Variables de entorno** (opcionales) en Netlify → *Site configuration → Environment
   variables*:
   - `ANTHROPIC_API_KEY` — tu API key de la Consola de Anthropic
     (https://console.anthropic.com/settings/keys). Sin esto, el bot responde con un
     error controlado; el resto de la app funciona normal.
   - `SUPABASE_JWT_SECRET` — solo si activaste Supabase. Project Settings → API → **JWT
     Secret** de tu proyecto. Con esto, la función del bot exige una sesión real (login)
     antes de contestar — nadie sin cuenta puede gastar tu crédito de API.
   - `APP_ACCESS_CODE` (opcional) — candado alterno si no usas Supabase pero igual quieres
     proteger el bot con una palabra clave.
5. Deploy — cada push a la rama conectada dispara un deploy automático.

### Probar localmente

```
npm install -g netlify-cli   # una sola vez
netlify dev                  # sirve public/ + netlify/functions/ juntos, con recarga
```

Necesitas un archivo `.env` (no se sube al repo) con `ANTHROPIC_API_KEY` y, si quieres
probar el candado del bot, `SUPABASE_JWT_SECRET`.

## Conexión bancaria automática (investigación preliminar — punto 4 del roadmap)

Para que los movimientos se registren solos hace falta conectar tus tarjetas/cuentas vía
un agregador de open finance regulado. En México los dos jugadores serios son:

| | **Belvo** | **Finerio Connect** |
|---|---|---|
| Sede / fundación | Brasil, 2019 | Ciudad de México, 2016 (jugador local) |
| Financiamiento | +USD $70M levantados | USD $6.5M levantados |
| Regulación | Autorizada por la CNBV como IFPE en México | No se encontró confirmación pública de autorización IFPE |
| Cobertura declarada | 60+ instituciones (BBVA, Banco Azteca, Banamex, entre otras); soporta cuentas de crédito | 120+ instituciones financieras integradas |
| Sandbox | Sandbox gratis e ilimitado para desarrollo | No verificado en esta investigación |
| Precio | No publicado — modelo de ventas/cotización | No publicado — modelo de ventas/cotización |

**Ninguno de los dos publica precios en su sitio** — ambos operan con un modelo de
"contacta a ventas", típico en open finance B2B. Antes de comprometerte con uno, vale la
pena: (a) probar el sandbox de Belvo sin costo para validar que cubre tus bancos/tarjetas
específicos, y (b) pedir cotización a ambos mencionando volumen esperado (una sola cuenta
al inicio) para ver si tienen un plan de entrada barato o si el mínimo es prohibitivo
para un producto todavía chico.

Belvo tiene la ventaja de la autorización CNBV confirmada y mayor escala regional;
Finerio Connect tiene la ventaja de ser 100% mexicana y reporta más instituciones
integradas. Ninguna conclusión aquí es definitiva — esto es un punto de partida para
cuando decidas invertir tiempo/dinero en este paso, no una recomendación final.

Fuentes: [Belvo — Plans and pricing](https://belvo.com/plans-and-pricing/) ·
[Belvo Developer Portal](https://developers.belvo.com/) ·
[Belvo | Latam Fintech Hub](https://www.latamfintech.co/companies/belvo) ·
[Finerio Connect](https://finerioconnect.com/en) ·
[Fintech Finerio untangles open banking in Mexico — Contxto](https://contxto.com/en/mexico/fintech-finerio-open-banking-mexico/) ·
[Compare Belvo vs Finerio Connect — CB Insights](https://www.cbinsights.com/compare/belvo-vs-finerio-connect)

**Importante**: esta conexión bancaria requiere el backend que ya está armado (login +
base de datos) — los tokens de acceso bancario tendrían que guardarse cifrados en el
servidor, nunca en el navegador. No se puede construir sobre la versión localStorage.

## Roadmap (según lo acordado)

1. ✅ Módulo de Proyecciones
2. ✅ Bot integrado (Claude)
3. ✅ Backend real: login (Supabase Auth) + base de datos (Postgres) + sync entre
   dispositivos.
4. ⏳ Conexión bancaria automática vía un agregador mexicano regulado (ver comparativo
   arriba) en vez de captura manual.
5. ⏳ Requisitos legales en México (LFPDPPP) si la app va a guardar datos financieros de
   terceros, no solo del dueño de la cuenta.
