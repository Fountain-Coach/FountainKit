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
  // Avoid double-injection
  if (!document.querySelector('script[data-chatkit-cdn]')) {
    const tag = document.createElement('script');
    tag.src = url;
    tag.defer = true;
    tag.setAttribute('data-chatkit-cdn', '1');
    document.head.appendChild(tag);
    await new Promise((resolve, reject) => {
      tag.addEventListener('load', resolve, { once: true });
      tag.addEventListener('error', () => reject(new Error('Failed to load ChatKit-JS CDN script')), { once: true });
      setTimeout(() => reject(new Error('Timed out loading ChatKit-JS CDN script')), 10000);
    });
  }
  if (typeof window.ChatKit?.mount !== 'function') {
    throw new Error('ChatKit-JS not available after CDN load');
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
