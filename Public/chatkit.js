const DEFAULTS = {
  apiBaseURL: '',
  elementId: 'chatkit-root',
  persona: 'default',
};

function log(...args) {
  // eslint-disable-next-line no-console
  console.log('[ChatKit]', ...args);
}

function logError(...args) {
  // eslint-disable-next-line no-console
  console.error('[ChatKit]', ...args);
}

async function createSession(config) {
  const response = await fetch(`${config.apiBaseURL}/chatkit/session`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      persona: config.persona,
      metadata: config.metadata ?? {},
    }),
  });
  if (!response.ok) {
    throw new Error(`Failed to create session (${response.status})`);
  }
  const headers = {};
  try { response.headers.forEach((v, k) => { headers[k] = v; }); } catch {}
  const session = await response.json();
  try {
    // Emit event without leaking the client secret
    const safe = {
      session_id: session.session_id,
      expires_at: session.expires_at,
    };
    window.dispatchEvent(new CustomEvent('chatkit:bootstrap:session', {
      detail: { status: response.status, headers, session: safe },
    }));
  } catch {}
  return session;
}

const DEFAULT_CDN = 'https://cdn.openai.com/chatkit/v1/chatkit.umd.js';

async function ensureChatKitLoaded(config) {
  if (typeof window.ChatKit?.mount === 'function') return;
  const url = (config && config.cdnUrl) || DEFAULT_CDN;

  // Try to find an existing CDN tag first
  let script = document.querySelector('script[data-chatkit-cdn]')
           || document.querySelector('script[src*="cdn.openai.com/chatkit/"]');

  const waitForLoad = (el) => new Promise((resolve, reject) => {
    let settled = false;
    const done = () => { if (!settled) { settled = true; resolve(); } };
    const fail = (msg) => { if (!settled) { settled = true; reject(new Error(msg)); } };
    // If the script element supports readyState (older browsers)
    if (el.readyState && (el.readyState === 'loaded' || el.readyState === 'complete')) {
      return resolve();
    }
    el.addEventListener('load', done, { once: true });
    el.addEventListener('error', () => fail('Failed to load ChatKit-JS CDN script'), { once: true });
    setTimeout(() => fail('Timed out loading ChatKit-JS CDN script'), 15000);
  });

  if (!script) {
    script = document.createElement('script');
    script.src = url;
    script.defer = true;
    script.crossOrigin = 'anonymous';
    script.setAttribute('data-chatkit-cdn', '1');
    document.head.appendChild(script);
  }

  try {
    await waitForLoad(script);
  } catch (e) {
    // Try local dev stub as a fallback
    window.dispatchEvent(new CustomEvent('chatkit:loader:fallback', { detail: { reason: (e && e.message) || 'cdn_error' } }));
    script = document.createElement('script');
    script.src = (config && config.localUrl) || '/Public/vendor/chatkit/chatkit.dev.js';
    script.defer = true;
    script.setAttribute('data-chatkit-cdn', 'dev-stub');
    document.head.appendChild(script);
    await waitForLoad(script);
  }

  // After the script tag has loaded, poll briefly for the global to attach
  const started = Date.now();
  while (typeof window.ChatKit?.mount !== 'function' && Date.now() - started < 2000) {
    await new Promise(r => setTimeout(r, 50));
  }
  if (typeof window.ChatKit?.mount !== 'function') {
    throw new Error('ChatKit-JS not available after load');
  }
}

async function mountChatKit(config, session) {
  await ensureChatKitLoaded(config);

  const target = document.getElementById(config.elementId);
  if (!target) {
    throw new Error(`Unable to find mount element #${config.elementId}`);
  }

  await window.ChatKit.mount({
    element: target,
    clientSecret: session.client_secret,
    apiBaseUrl: config.apiBaseURL || window.location.origin,
    threads: {
      autoCreate: true,
    },
  });
}

async function bootstrapChatKit(userConfig = {}) {
  const config = { ...DEFAULTS, ...userConfig };
  try {
    log('Bootstrapping ChatKit client…');
    try { window.dispatchEvent(new CustomEvent('chatkit:bootstrap:start', { detail: { config } })); } catch {}
    const session = await createSession(config);
    await mountChatKit(config, session);
    log('ChatKit mounted', { sessionId: session.session_id });
    try { window.dispatchEvent(new CustomEvent('chatkit:bootstrap:mounted', { detail: { sessionId: session.session_id } })); } catch {}
  } catch (error) {
    logError('Failed to initialize ChatKit', error);
    const target = document.getElementById(config.elementId);
    if (target) {
      target.innerHTML = `
        <div class="chatkit-error" role="alert">
          <strong>ChatKit failed to load.</strong>
          <p>${error.message}</p>
          <p>Check browser console logs for additional details.</p>
        </div>
      `;
    }
    try { window.dispatchEvent(new CustomEvent('chatkit:bootstrap:error', { detail: { message: error?.message ?? String(error) } })); } catch {}
    throw error;
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const bootstrapConfig = window.chatkitConfig || {};
  if (bootstrapConfig.auto === false) {
    log('Auto bootstrap disabled; waiting for manual init.');
    return;
  }
  bootstrapChatKit(bootstrapConfig);
});

export { bootstrapChatKit };
