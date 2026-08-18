const qp = new URLSearchParams(window.location.search);
const festivalId = (qp.get('festivalId') || '').trim();
const userId = (qp.get('userId') || '').trim();
const alias = (qp.get('alias') || '').trim();
const platform = (qp.get('platform') || 'web').trim();

const apiBase = 'api.php';
const meta = document.getElementById('meta');
const joinBtn = document.getElementById('joinBtn');
const leaveBtn = document.getElementById('leaveBtn');
const messagesEl = document.getElementById('messages');
const composer = document.getElementById('composer');
const input = document.getElementById('messageInput');
const statusEl = document.getElementById('status');

let joined = false;
let me = { userId, alias };
let lastSeen = 0;
let mentionUnread = 0;
let pollTimer = null;
let pollDelayMs = 2500;
let consecutiveErrors = 0;
let isJoining = false;
let isLeaving = false;
let isSending = false;

meta.textContent = `${festivalId || 'festival-desconocido'} · ${alias || 'anonimo'} · ${platform}`;

function esc(str) {
  return String(str)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function fmtTime(ts) {
  return new Date(ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function titleUpdate() {
  document.title = mentionUnread > 0 ? `(${mentionUnread}) Chat del Festival` : 'Chat del Festival';
}

function setStatus(message, kind = 'info') {
  if (!statusEl) {
    return;
  }
  statusEl.textContent = message || '';
  statusEl.classList.remove('error', 'ok');
  if (kind === 'error') {
    statusEl.classList.add('error');
  }
  if (kind === 'ok') {
    statusEl.classList.add('ok');
  }
}

function describeError(err) {
  if (!err) {
    return 'Error inesperado.';
  }
  if (err.message === 'rate_limited') {
    return 'Demasiadas acciones seguidas. Espera un momento.';
  }
  if (err.message === 'timeout') {
    return 'Tiempo de espera agotado. Reintentando...';
  }
  return 'No se pudo completar la accion. Reintentando...';
}

async function api(action, body = null, method = 'POST') {
  const url = `${apiBase}?action=${encodeURIComponent(action)}`;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 10000);
  const opts = { method, headers: {} };
  if (body) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  opts.signal = controller.signal;

  let res;
  try {
    res = await fetch(url, opts);
  } catch (err) {
    clearTimeout(timeoutId);
    if (err && err.name === 'AbortError') {
      throw new Error('timeout');
    }
    throw err;
  }
  clearTimeout(timeoutId);

  let payload = {};
  try {
    payload = await res.json();
  } catch {
    payload = {};
  }

  if (!res.ok) {
    throw new Error(payload.error || `HTTP_${res.status}`);
  }
  return payload;
}

function renderMessages(list) {
  messagesEl.innerHTML = '';
  for (const m of list) {
    const div = document.createElement('div');
    div.className = `msg ${m.userId === me.userId ? 'me' : ''}`;

    const safeAlias = esc(m.alias);
    const safeBody = esc(m.text).replace(/@([A-Za-z0-9_-]{3,24})/g, '<span class="mention">@$1</span>');

    div.innerHTML = `
      <div class="meta">${safeAlias} · ${fmtTime(m.createdAt)}</div>
      <div class="body">${safeBody}</div>
    `;
    messagesEl.appendChild(div);

    if (m.createdAt > lastSeen) {
      lastSeen = m.createdAt;
    }
  }
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

async function refreshMessages() {
  if (!joined) {
    return;
  }

  try {
    const out = await api('messages', { festivalId, userId: me.userId });
    const list = out.messages || [];

    // mention-only notifications
    if (document.hidden) {
      for (const m of list) {
        if (m.createdAt <= lastSeen) {
          continue;
        }
        const mentionsMe = Array.isArray(m.mentions) && m.mentions.includes(me.userId);
        if (mentionsMe && m.userId !== me.userId) {
          mentionUnread += 1;
          titleUpdate();
        }
      }
    }

    renderMessages(list);
    consecutiveErrors = 0;
    pollDelayMs = 2500;
    setStatus('Conectado', 'ok');
  } catch (err) {
    console.error(err);
    consecutiveErrors += 1;
    pollDelayMs = Math.min(12000, 2500 * (consecutiveErrors + 1));
    setStatus(`Conexion inestable. ${describeError(err)}`, 'error');
  }
}

function syncButtons() {
  joinBtn.disabled = joined || isJoining || isLeaving || isSending;
  leaveBtn.disabled = !joined || isJoining || isLeaving || isSending;
  input.disabled = false;
  input.placeholder = joined
    ? 'Escribe un mensaje...'
    : 'Pulsa Unirse o escribe para unirte automaticamente...';
}

async function joinChat() {
  if (isJoining) {
    return;
  }
  isJoining = true;
  syncButtons();

  try {
    const out = await api('join', { festivalId, userId: me.userId, alias: me.alias });
    joined = !!out.joined;
    setStatus('Te has unido al chat.', 'ok');
    await refreshMessages();
  } finally {
    isJoining = false;
    syncButtons();
  }
}

async function leaveChat() {
  if (isLeaving) {
    return;
  }
  isLeaving = true;
  syncButtons();

  try {
    await api('leave', { festivalId, userId: me.userId });
    joined = false;
    messagesEl.innerHTML = '';
    lastSeen = 0;
    mentionUnread = 0;
    input.value = '';
    await clearLocalChatFootprint();
    titleUpdate();
    setStatus('Has abandonado el chat. El historial local se ha limpiado.', 'ok');
  } finally {
    isLeaving = false;
    syncButtons();
  }
}

async function clearLocalChatFootprint() {
  try {
    const prefixes = ['ft-chat', 'festtime.chat'];

    try {
      const lsKeys = [];
      for (let i = 0; i < localStorage.length; i += 1) {
        const key = localStorage.key(i);
        if (key) {
          lsKeys.push(key);
        }
      }
      for (const key of lsKeys) {
        if (prefixes.some((prefix) => key.startsWith(prefix))) {
          localStorage.removeItem(key);
        }
      }
    } catch (_) {}

    try {
      const ssKeys = [];
      for (let i = 0; i < sessionStorage.length; i += 1) {
        const key = sessionStorage.key(i);
        if (key) {
          ssKeys.push(key);
        }
      }
      for (const key of ssKeys) {
        if (prefixes.some((prefix) => key.startsWith(prefix))) {
          sessionStorage.removeItem(key);
        }
      }
    } catch (_) {}

    if (window.caches && caches.keys) {
      const cacheNames = await caches.keys();
      await Promise.all(
        cacheNames
          .filter((name) => name.includes('chat') || name.includes('festtime'))
          .map((name) => caches.delete(name))
      );
    }
  } catch (_) {}
}

function scheduleNextPoll() {
  if (pollTimer) {
    clearTimeout(pollTimer);
  }
  pollTimer = setTimeout(async () => {
    await refreshMessages();
    scheduleNextPoll();
  }, pollDelayMs);
}

joinBtn.addEventListener('click', async () => {
  try { await joinChat(); } catch (err) { console.error(err); }
});

leaveBtn.addEventListener('click', async () => {
  try { await leaveChat(); } catch (err) { console.error(err); }
});

composer.addEventListener('submit', async (ev) => {
  ev.preventDefault();
  if (isSending || isLeaving) {
    return;
  }

  const text = input.value.trim();
  if (!text) {
    return;
  }

  if (!joined) {
    try {
      await joinChat();
    } catch (err) {
      console.error(err);
      return;
    }
  }

  if (!joined) {
    return;
  }

  isSending = true;
  syncButtons();
  input.value = '';

  try {
    await api('send', { festivalId, userId: me.userId, alias: me.alias, text });
    setStatus('Mensaje enviado', 'ok');
    await refreshMessages();
  } catch (err) {
    console.error(err);
    setStatus(describeError(err), 'error');
  } finally {
    isSending = false;
    syncButtons();
  }
});

input.addEventListener('focus', async () => {
  if (joined) {
    return;
  }

  try {
    await joinChat();
  } catch (err) {
    console.error(err);
  }
});

document.addEventListener('visibilitychange', () => {
  if (!document.hidden) {
    mentionUnread = 0;
    titleUpdate();
  }
});

(async function boot() {
  if (!festivalId || !userId || !alias) {
    alert('Faltan parametros de chat.');
    return;
  }

  try {
    const session = await api('session', { userId, alias, platform });
    me = { userId: session.userId, alias: session.alias };
    meta.textContent = `${festivalId} · ${me.alias} · ${platform}`;
    const status = await api('status', { festivalId, userId: me.userId });
    joined = !!status.joined;
    syncButtons();
    if (joined) {
      await refreshMessages();
      setStatus('Conectado', 'ok');
    } else {
      setStatus('Pulsa Unirse al chat para empezar.', 'info');
    }
    scheduleNextPoll();
  } catch (err) {
    console.error(err);
    setStatus(describeError(err), 'error');
    scheduleNextPoll();
  }
})();
