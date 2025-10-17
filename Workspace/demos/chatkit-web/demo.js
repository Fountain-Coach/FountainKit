import { bootstrapChatKit } from "../../../Public/chatkit.js";

const qs = new URLSearchParams(window.location.search);
const DEFAULT_BASE = "http://127.0.0.1:8010";
const defaultPersona = qs.get("persona")?.trim() || "demo";
const defaultBase = qs.get("base")?.trim() || DEFAULT_BASE;

const form = document.querySelector("#config-form");
const gatewayInput = document.querySelector("#gateway");
const personaInput = document.querySelector("#persona");
const statusEl = document.querySelector("#status");
const resetBtn = document.querySelector("#reset-config");
const logEl = document.querySelector("#debug-log");
const copyBtn = document.querySelector("#copy-logs");
const clearBtn = document.querySelector("#clear-logs");

gatewayInput.value = defaultBase;
personaInput.value = defaultPersona;

function setStatus(message, variant = "info") {
  if (!statusEl) return;
  statusEl.textContent = message;
  statusEl.classList.toggle("error", variant === "error");
}

function ts() {
  return new Date().toISOString();
}

function logLine(kind, obj) {
  if (!logEl) return;
  const line = `[${ts()}] ${kind} ${typeof obj === "string" ? obj : JSON.stringify(obj)}\n`;
  logEl.textContent += line;
  logEl.scrollTop = logEl.scrollHeight;
}

function logEnv() {
  logLine("env", {
    location: window.location.href,
    origin: window.location.origin,
    userAgent: navigator.userAgent,
    defaultBase,
    defaultPersona,
  });
}

async function healthCheck(baseURL) {
  const url = `${baseURL.replace(/\/$/, "")}/health`;
  try {
    const res = await fetch(url, { method: "GET" });
    const headers = {};
    try { res.headers.forEach((v, k) => headers[k] = v); } catch {}
    logLine("health", { url, status: res.status, headers });
  } catch (e) {
    logLine("health_error", { url, message: e?.message || String(e) });
  }
}

let reconnectTimer = null;
let backoffMs = 2000;
const backoffMaxMs = 30000;

function scheduleReconnect(why) {
  if (reconnectTimer) return; // already scheduled
  const delay = backoffMs;
  backoffMs = Math.min(backoffMaxMs, Math.floor(backoffMs * 1.8));
  logLine("reconnect_scheduled", { delay, reason: why });
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect(gatewayInput.value, personaInput.value);
  }, delay);
}

function resetBackoff() {
  backoffMs = 2000;
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
}

async function connect(baseURL, persona) {
  const trimmedBase = baseURL.trim().replace(/\/$/, "");
  const trimmedPersona = persona.trim() || "demo";

  window.chatkitConfig = {
    auto: false,
    apiBaseURL: trimmedBase,
    persona: trimmedPersona,
    metadata: {
      source: "chatkit-web-demo",
      persona: trimmedPersona,
    },
  };

  setStatus(`Connecting to ${trimmedBase}…`);
  logLine("connect", { base: trimmedBase, persona: trimmedPersona });
  await healthCheck(trimmedBase);
  try {
    await bootstrapChatKit(window.chatkitConfig);
    setStatus(`Connected to ${trimmedBase} as persona "${trimmedPersona}".`);
    logLine("mounted", { base: trimmedBase, persona: trimmedPersona });
    resetBackoff();
  } catch (error) {
    console.error("[ChatKit demo] bootstrap failed", error);
    setStatus(error.message ?? "Failed to bootstrap ChatKit.", "error");
    logLine("error", { message: error?.message || String(error) });
    scheduleReconnect("bootstrap_error");
  }
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  connect(gatewayInput.value, personaInput.value);
});

resetBtn.addEventListener("click", () => {
  gatewayInput.value = DEFAULT_BASE;
  personaInput.value = "demo";
  connect(DEFAULT_BASE, "demo");
});

// Bootstrap immediately with defaults.
logEnv();
connect(defaultBase, defaultPersona);

// Wire debug actions
copyBtn?.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(logEl?.textContent || "");
    setStatus("Logs copied to clipboard.");
  } catch {
    setStatus("Failed to copy logs.", "error");
  }
});

clearBtn?.addEventListener("click", () => {
  if (logEl) logEl.textContent = "";
});

// Listen for helper lifecycle events
window.addEventListener("chatkit:bootstrap:start", (e) => {
  const detail = e.detail || {};
  logLine("bootstrap_start", { base: detail?.config?.apiBaseURL, persona: detail?.config?.persona });
});

window.addEventListener("chatkit:bootstrap:session", (e) => {
  const d = e.detail || {};
  logLine("session", { status: d.status, headers: d.headers, session: d.session });
});

window.addEventListener("chatkit:bootstrap:mounted", (e) => {
  const d = e.detail || {};
  logLine("mounted_event", { sessionId: d.sessionId });
  resetBackoff();
});

window.addEventListener("chatkit:bootstrap:error", (e) => {
  const d = e.detail || {};
  logLine("bootstrap_error", d);
  scheduleReconnect("bootstrap_event_error");
});

// Try to reconnect when the tab becomes visible again (e.g., after restart)
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    scheduleReconnect("tab_visible");
  }
});
