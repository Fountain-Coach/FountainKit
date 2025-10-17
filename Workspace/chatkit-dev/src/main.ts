import '../../Public/styles.css';
import { bootstrapChatKit } from '../../Public/chatkit.js';

const app = document.getElementById('app')!;
app.innerHTML = `
  <main class="chatkit-shell">
    <header>
      <h1>ChatKit Dev</h1>
      <p class="subtitle">Vite dev server with proxy to the gateway.</p>
    </header>
    <section class="config">
      <label>Gateway URL <input id="gateway" value="/" /></label>
      <label>Persona <input id="persona" value="dev" /></label>
      <button id="connect">Connect</button>
    </section>
    <section class="chatkit-container"><div id="chatkit-root"></div></section>
    <section class="debug"><pre id="log"></pre></section>
  </main>
`;

const gw = document.getElementById('gateway') as HTMLInputElement;
const persona = document.getElementById('persona') as HTMLInputElement;
const btn = document.getElementById('connect') as HTMLButtonElement;
const logEl = document.getElementById('log') as HTMLPreElement;

function ts() { return new Date().toISOString(); }
function log(kind: string, data: any) {
  logEl.textContent += `[${ts()}] ${kind} ${typeof data === 'string' ? data : JSON.stringify(data)}\n`;
  logEl.scrollTop = logEl.scrollHeight;
}

// Default to same-origin proxy ("/") so /chatkit routes hit the vite proxy
gw.value = '/';

btn.addEventListener('click', async () => {
  const base = (gw.value || '/').trim().replace(/\/$/, '');
  const p = (persona.value || 'dev').trim();
  log('connect', { base, persona: p });
  try {
    await bootstrapChatKit({ apiBaseURL: base || '/', persona: p, metadata: { source: 'vite-dev' } });
    log('mounted', { base, persona: p });
  } catch (e: any) {
    log('error', e?.message || String(e));
  }
});

window.addEventListener('chatkit:bootstrap:start', (e: any) => log('bootstrap_start', e.detail));
window.addEventListener('chatkit:bootstrap:session', (e: any) => log('session', e.detail));
window.addEventListener('chatkit:bootstrap:mounted', (e: any) => log('mounted_event', e.detail));
window.addEventListener('chatkit:bootstrap:error', (e: any) => log('bootstrap_error', e.detail));

