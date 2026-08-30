// Puente entre la app y la API de Claude. Corre en el servidor (Netlify Functions)
// para que la API key nunca quede expuesta en el navegador.

const MAX_QUESTION_LEN = 2000;
const MAX_CONTEXT_LEN = 20000; // límite defensivo sobre el tamaño del contexto financiero recibido

exports.handler = async function (event) {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: JSON.stringify({ error: 'Method Not Allowed' }) };
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    return {
      statusCode: 500,
      body: JSON.stringify({ error: 'El servidor no tiene configurada ANTHROPIC_API_KEY.' }),
    };
  }

  // Gate opcional y ligero: si el sitio define APP_ACCESS_CODE, exige que el cliente lo mande.
  // Es una medida mínima mientras no exista login real (eso llega con el backend, más adelante).
  const requiredCode = process.env.APP_ACCESS_CODE;
  if (requiredCode) {
    const provided = event.headers['x-app-code'] || event.headers['X-App-Code'];
    if (provided !== requiredCode) {
      return { statusCode: 401, body: JSON.stringify({ error: 'Código de acceso inválido.' }) };
    }
  }

  let payload;
  try {
    payload = JSON.parse(event.body || '{}');
  } catch (e) {
    return { statusCode: 400, body: JSON.stringify({ error: 'JSON inválido.' }) };
  }

  const question = typeof payload.question === 'string' ? payload.question.trim() : '';
  const financialContext = payload.context;

  if (!question) {
    return { statusCode: 400, body: JSON.stringify({ error: 'Falta la pregunta.' }) };
  }
  if (question.length > MAX_QUESTION_LEN) {
    return { statusCode: 400, body: JSON.stringify({ error: 'La pregunta es demasiado larga.' }) };
  }
  if (!financialContext || typeof financialContext !== 'object') {
    return { statusCode: 400, body: JSON.stringify({ error: 'Falta el contexto financiero.' }) };
  }
  const contextStr = JSON.stringify(financialContext);
  if (contextStr.length > MAX_CONTEXT_LEN) {
    return { statusCode: 400, body: JSON.stringify({ error: 'El contexto financiero es demasiado grande.' }) };
  }

  const systemPrompt = [
    'Eres un asesor financiero personal, directo y honesto. Respondes en español, en menos de 180 palabras.',
    'A continuación tienes el contexto financiero ACTUAL del usuario, generado automáticamente por su app (ingresos, gastos fijos, deuda, avance de ahorro del mes y sus gastos futuros ya planeados).',
    'Úsalo como única fuente de verdad numérica: no inventes cifras que no estén ahí.',
    'Contexto financiero (JSON):',
    contextStr,
    '',
    'Da una recomendación clara y accionable sobre la pregunta del usuario. Si el gasto no es prudente en este momento, dilo directamente y explica por qué (deuda cara, ritmo de gasto, meta de ahorro atrasada, etc.). Si sí es prudente, dilo también y por qué.',
  ].join('\n');

  try {
    const resp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: process.env.CLAUDE_MODEL || 'claude-sonnet-5',
        max_tokens: 600,
        system: systemPrompt,
        messages: [{ role: 'user', content: question }],
      }),
    });

    const data = await resp.json();

    if (!resp.ok) {
      const message = (data && data.error && data.error.message) || 'Error al llamar a Claude.';
      return { statusCode: resp.status, body: JSON.stringify({ error: message }) };
    }

    const answer = (data.content || [])
      .map((block) => block.text || '')
      .join('\n')
      .trim();

    return { statusCode: 200, body: JSON.stringify({ answer }) };
  } catch (e) {
    return { statusCode: 502, body: JSON.stringify({ error: 'No se pudo contactar a Claude en este momento.' }) };
  }
};
