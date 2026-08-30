# Panel — Finanzas personales

App de finanzas personales (registro diario, alertas, proyecciones de gastos futuros y
un bot integrado que responde con Claude usando tu contexto financiero actual).

## Estructura

```
public/index.html           App (una sola página, sin build). Sigue viviendo de localStorage
                             por ahora — la migración a backend/DB es el siguiente paso.
netlify/functions/ask-bot.js Función serverless: llama a la API de Claude con tu API key
                             guardada en el servidor. El navegador nunca ve la API key.
netlify.toml                 Config de Netlify (publish dir + functions dir).
```

## Módulos nuevos

- **Proyectar**: apartas un gasto futuro (qué, cuánto, para cuándo) y la app te da un
  semáforo (✓/⚠/✗) evaluando tu presupuesto de Diversión/Libre restante, tu avance de
  ahorro del mes y si tienes deuda generando interés. La lógica vive en
  `evaluateProjection()` dentro de `public/index.html` — es una heurística transparente,
  no una llamada a IA, así que siempre puedes ver los números detrás de la recomendación.
- **Pregúntale a Claude**: dentro de la misma pestaña, un cuadro de chat que manda tu
  pregunta + un resumen de tu situación financiera actual (`buildFinancialContext()`) a
  la función `ask-bot`, que la reenvía a la API de Claude.

## Puesta en marcha (Netlify)

1. **Conectar el repo a Netlify** (si tu sitio actual fue un deploy manual del HTML
   suelto, tienes que volver a conectarlo): en Netlify → *Add new site* → *Import an
   existing project* → selecciona este repo. Build command: vacío. Publish directory:
   `public`. Functions directory: `netlify/functions` (Netlify lo detecta solo desde
   `netlify.toml`).
2. **Variable de entorno obligatoria para el bot**: en Netlify → *Site configuration* →
   *Environment variables*, agrega:
   - `ANTHROPIC_API_KEY` — tu API key de la Consola de Anthropic
     (https://console.anthropic.com/settings/keys). Sin esto, el botón "Preguntar"
     responde con un error controlado, el resto de la app sigue funcionando normal.
3. **Opcional — candado simple para el bot**: si te preocupa que alguien más use tu URL
   y consuma tu crédito de API, agrega también `APP_ACCESS_CODE` con cualquier palabra
   clave. Luego, en la app, ve a Ajustes → "Bot" y pon esa misma palabra en "Código de
   acceso". Esto no es autenticación real (eso llega con el backend/login del punto 3
   del roadmap), es solo una fricción extra mientras tanto.
4. **Deploy** — cada push a la rama conectada dispara un deploy automático.

### Probar localmente

```
npm install -g netlify-cli   # una sola vez
netlify dev                  # sirve public/ + netlify/functions/ juntos, con recarga
```

Para probar el bot en local necesitas un archivo `.env` (no se sube al repo) con:

```
ANTHROPIC_API_KEY=sk-ant-...
```

## Roadmap (según lo acordado)

1. ✅ Módulo de Proyecciones
2. ✅ Bot integrado (Claude)
3. ⏳ Backend real: login, base de datos, sync entre dispositivos (hoy vive en
   localStorage y se puede perder si cambias de teléfono o borras datos del navegador).
4. ⏳ Conexión bancaria automática vía un agregador mexicano regulado (Belvo o Finerio
   Connect) en vez de captura manual.
5. ⏳ Requisitos legales en México (LFPDPPP) si la app va a guardar datos financieros de
   terceros, no solo del dueño de la cuenta.
