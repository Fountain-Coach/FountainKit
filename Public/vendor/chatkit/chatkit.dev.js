;(function(){
  function h(tag, attrs, children){
    const el = document.createElement(tag);
    if (attrs) for (const k in attrs) el.setAttribute(k, attrs[k]);
    (children||[]).forEach(c => el.appendChild(typeof c==='string'?document.createTextNode(c):c));
    return el;
  }
  async function postJSON(url, body){
    const res = await fetch(url, {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)});
    if (!res.ok) throw new Error('HTTP '+res.status);
    return res.json();
  }
  async function postStream(url, body){
    const res = await fetch(url, {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)});
    if (!res.ok) throw new Error('HTTP '+res.status);
    const text = await res.text();
    return text;
  }
  window.ChatKit = window.ChatKit || {};
  window.ChatKit.mount = async function mount(opts){
    const root = opts.element;
    root.innerHTML='';
    const header = h('div', {class: 'ck-dev-header'}, [
      h('strong', null, ['ChatKit Dev Stub']),
      h('span', {style:'margin-left:8px;color:#667085;'}, [`model persona: ${opts.threads?.autoCreate? 'auto' : 'manual'}`])
    ]);
    const log = h('pre', {class:'ck-dev-log'});
    const form = h('form', {class:'ck-dev-form'}, [
      h('textarea', {rows:'3', placeholder:'Type a message...'}),
      h('div', {class:'ck-dev-actions'}, [h('button', {type:'submit'}, ['Send'])])
    ]);
    const messages = h('div', {class:'ck-dev-messages'});
    root.append(header, form, messages, log);
    function logLine(kind, data){
      const line = `[${new Date().toISOString()}] ${kind} ${typeof data==='string'?data:JSON.stringify(data)}\n`;
      log.textContent += line; log.scrollTop = log.scrollHeight;
    }
    // initial system message
    messages.append(h('div', {class:'msg sys'}, ['Connected. Using dev stub widget.']));
    form.addEventListener('submit', async (e)=>{
      e.preventDefault();
      const textarea = form.querySelector('textarea');
      const content = textarea.value.trim();
      if(!content) return;
      textarea.value='';
      messages.append(h('div', {class:'msg user'}, [content]));
      try{
        const payload = { client_secret: opts.clientSecret, messages:[{role:'user', content}], stream: false };
        const resp = await postJSON(opts.apiBaseUrl.replace(/\/$/,'') + '/chatkit/messages', payload);
        messages.append(h('div', {class:'msg bot'}, [resp.answer || '(no answer)']));
      }catch(err){
        logLine('error', err.message || String(err));
      }
    });
  };
})();

