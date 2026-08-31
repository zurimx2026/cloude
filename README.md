# Panel — Finanzas personales

App de finanzas personales: registro diario, alertas, proyecciones de gastos futuros,
un bot integrado que responde con Claude usando tu contexto financiero actual, y ahora
login + base de datos en la nube (Supabase) con sincronización entre dispositivos.

## Estructura

```
public/index.html            App (una sola página, sin build). Requiere sesión (Supabase
                              Auth); todos los datos viven en Postgres, no en localStorage.
public/config.example.js     Plantilla de config.js (URL + anon key de tu proyecto Supabase).
netlify/functions/ask-bot.js Función serverless: llama a la API de Claude con tu API key
                              guardada en el servidor, y valida que quien pregunta tenga
                              sesión real. El navegador nunca ve la API key.
netlify.toml                  Config de Netlify (publish dir + functions dir).
supabase/schema.sql           Esquema de base de datos (tablas + Row Level Security).
```

## Módulos

- **Proyectar**: apartas un gasto futuro (qué, cuánto, para cuándo) y la app te da un
  semáforo (✓/⚠/✗) evaluando tu presupuesto de Diversión/Libre restante, tu avance de
  ahorro del mes y si tienes deuda generando interés. La lógica vive en
  `evaluateProjection()` dentro de `public/index.html` — es una heurística transparente,
  no una llamada a IA, así que siempre puedes ver los números detrás de la recomendación.
- **Pregúntale a Claude**: dentro de la misma pestaña, un cuadro de chat que manda tu
  pregunta + un resumen de tu situación financiera actual (`buildFinancialContext()`) a
  la función `ask-bot`, que la reenvía a la API de Claude.
- **Cuenta**: login con correo y contraseña (Supabase Auth). Tus datos (config, gastos
  fijos, deudas, movimientos, proyecciones) se guardan en Postgres, aislados por usuario
  con Row Level Security — sincronizan solos entre tu teléfono y cualquier otro
  dispositivo donde inicies sesión. Si la app detecta datos viejos guardados en el
  navegador (de la versión anterior con localStorage), te ofrece importarlos a tu cuenta
  la primera vez que inicias sesión.

## Puesta en marcha

### 1. Crear el proyecto de Supabase (base de datos + login)

1. Crea una cuenta gratis en [supabase.com](https://supabase.com) y un proyecto nuevo.
2. Ve a **SQL Editor** → pega el contenido completo de `supabase/schema.sql` → *Run*.
   Esto crea las tablas, activa Row Level Security, y un trigger que le crea su fila de
   perfil a cada cuenta nueva automáticamente.
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
2. `public/config.js` está en `.gitignore` porque cada quien pone ahí los valores de su
   propio proyecto de Supabase — pero como es un sitio conectado a git (deploy continuo),
   Netlify solo sirve lo que esté en el repo. La forma más simple: quita esa línea de
   `.gitignore` y haz commit de tu `config.js` real — no pasa nada porque la anon key es
   segura para ser pública (la protección de verdad es el Row Level Security del paso
   anterior). Si prefieres no tenerlo en git, la alternativa es agregar un build command
   en Netlify que lo genere en cada deploy a partir de variables de entorno (`echo
   "window.SUPABASE_URL='$SUPABASE_URL'; window.SUPABASE_ANON_KEY='$SUPABASE_ANON_KEY';" >
   public/config.js`), configurando esas dos variables en Netlify.
3. **Variables de entorno** en Netlify → *Site configuration → Environment variables*:
   - `ANTHROPIC_API_KEY` — tu API key de la Consola de Anthropic
     (https://console.anthropic.com/settings/keys). Sin esto, el bot responde con un
     error controlado; el resto de la app funciona normal.
   - `SUPABASE_JWT_SECRET` — Project Settings → API → **JWT Secret** de tu proyecto
     Supabase. Con esto, la función del bot exige una sesión real (login) antes de
     contestar — nadie sin cuenta puede gastar tu crédito de API.
   - `APP_ACCESS_CODE` (opcional) — candado alterno si por alguna razón no configuras
     `SUPABASE_JWT_SECRET`.
4. Deploy — cada push a la rama conectada dispara un deploy automático.

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
