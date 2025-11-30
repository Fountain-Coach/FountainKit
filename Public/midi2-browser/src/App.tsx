import { useEffect, useMemo, useState } from 'react'
import './App.css'
import { makeHarness } from './midi2Harness'
import { midiBase, semanticBase } from './config'
import { bytesToWords } from './ump'

type Tab = {
  id: string
  title: string
  url: string
}

const initialTabs: Tab[] = [
  { id: 't1', title: 'Atlas Home', url: 'https://example.com' },
  { id: 't2', title: 'MIDI2 Playground', url: 'https://midi.tools/' }
]

function App() {
  const harness = useMemo(() => makeHarness(), [])
  const [tabs, setTabs] = useState<Tab[]>(() => {
    const fromStorage = localStorage.getItem('midi2-browser-tabs')
    if (fromStorage) {
      try { return JSON.parse(fromStorage) as Tab[] } catch { return initialTabs }
    }
    return initialTabs
  })
  const [currentUrl, setCurrentUrl] = useState(tabs[0]?.url ?? initialTabs[0].url)
  const [activeTabId, setActiveTabId] = useState(tabs[0]?.id ?? initialTabs[0].id)
  const [domPreview, setDomPreview] = useState<string>('Ready to navigate.')
  const [netPreview, setNetPreview] = useState<string>('No captures yet.')
  const [logs, setLogs] = useState<string[]>([])
  const [loading, setLoading] = useState(false)
  const [tail, setTail] = useState<string>('No UMP events yet.')
  const [screenshotUrl, setScreenshotUrl] = useState<string | undefined>(undefined)
  const [injectEnabled, setInjectEnabled] = useState(false)

  const log = (msg: string) => setLogs((l) => [...l.slice(-30), msg])

  useEffect(() => {
    localStorage.setItem('midi2-browser-tabs', JSON.stringify(tabs))
  }, [tabs])

  const navigate = async () => {
    setLoading(true)
    try {
      const res = await fetch(`${semanticBase}/v1/snapshot`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          url: currentUrl,
          wait: { strategy: 'networkIdle', networkIdleMs: 300, maxWaitMs: 8000 },
          storeArtifacts: false
        })
      })
      if (!res.ok) throw new Error(`snapshot failed: ${res.status}`)
      type SnapshotPayload = {
        snapshot?: {
          rendered?: { text?: string }
          network?: unknown
          page?: { finalUrl?: string }
          rendered?: { image?: { imageId?: string } }
        }
      }
      const body: SnapshotPayload = await res.json()
      const snap = body.snapshot
      setDomPreview(snap?.rendered?.text ?? '(no text)')
      setNetPreview(JSON.stringify(snap?.network ?? {}, null, 2).slice(0, 2000))
      log(`snapshot ok ${snap?.page?.finalUrl ?? currentUrl}`)
      const imageId = snap?.rendered?.image?.imageId
      if (imageId) {
        setScreenshotUrl(`${semanticBase}/assets/${imageId}.png`)
      } else {
        setScreenshotUrl(undefined)
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      log(`snapshot error: ${message}`)
      setDomPreview('Error fetching snapshot.')
    } finally {
      setLoading(false)
    }
  }

  const sendTestNote = async () => {
    // Note on middle C
    const msg = harness.noteOn(0, 0, 60, 0x7fff)
    try {
      const words = bytesToWords(msg)
      await fetch(`${midiBase}/ump/send`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ target: { displayName: 'Loopback' }, words })
      })
      log('sent noteOn via midi-service')
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      log(`midi send error: ${message}`)
    }
  }

  const tailUmp = async () => {
    try {
      const res = await fetch(`${midiBase}/ump/events?limit=20`)
      if (!res.ok) throw new Error(`tail failed ${res.status}`)
      const body: { events?: Array<{ ts?: number; words?: number[] }> } = await res.json()
      const lines =
        body?.events?.map((e) => {
          const arr = e.words ?? []
          const hex = arr.map((w) => w.toString(16).padStart(8, '0')).join(' ')
          return `[${e.ts ?? ''}] ${hex}`
        }) ?? []
      setTail(lines.length ? lines.join('\n') : 'No UMP events yet.')
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      setTail(`UMP tail error: ${message}`)
    }
  }

  useEffect(() => {
    tailUmp()
  }, [])

  const toggleInject = () => {
    setInjectEnabled((v) => {
      const next = !v
      log(next ? 'midi2.js injection toggled on (stub)' : 'midi2.js injection toggled off')
      return next
    })
  }

  const addTab = () => {
    const id = `t${Date.now()}`
    const tab = { id, title: 'New Tab', url: 'https://example.com' }
    setTabs((t) => [...t, tab])
    setActiveTabId(id)
    setCurrentUrl(tab.url)
  }

  return (
    <div className="app-shell">
      <div className="topbar">
        <span className="pill">midi2.js</span>
        <div>
          <h1 className="title">MIDI2 Browser</h1>
          <p className="subtitle">Atlas-like browsing with MIDI 2.0 control and UMP inspection</p>
        </div>
      </div>

      <div className="grid">
        <div className="panel">
          <h3>Tabs</h3>
          <div className="tabs">
            {initialTabs.map((tab) => (
              <div
                key={tab.id}
                className={`tab ${tab.id === activeTabId ? 'active' : ''}`}
                onClick={() => {
                  setActiveTabId(tab.id)
                  setCurrentUrl(tab.url)
                }}
              >
                {tab.title}
              </div>
            ))}
            <button className="btn secondary" onClick={addTab}>+ New Tab</button>
          </div>

          <div className="address-bar">
            <button className="btn secondary">◀</button>
            <input placeholder="https://…" value={currentUrl} onChange={(e) => setCurrentUrl(e.target.value)} />
            <button className="btn" onClick={navigate} disabled={loading}>
              {loading ? 'Loading…' : 'Navigate'}
            </button>
          </div>

          <div className="panel" style={{ flex: 1, marginTop: 10 }}>
            <h3>Page Preview</h3>
            <div className="split">
              <div className="panel" style={{ height: 240 }}>
                <h3>DOM</h3>
                <div className="ump-list" style={{ background: '#0f172a', height: 180 }}>
                  {domPreview}
                </div>
              </div>
              <div className="panel" style={{ height: 240 }}>
                <h3>Network</h3>
                <div className="ump-list" style={{ background: '#0f172a', height: 180 }}>
                  <pre style={{ whiteSpace: 'pre-wrap', margin: 0 }}>{netPreview}</pre>
                </div>
              </div>
              <div className="panel" style={{ gridColumn: '1 / span 2', height: 260 }}>
                <h3>Screenshot</h3>
                {screenshotUrl ? (
                  <img src={screenshotUrl} alt="Page screenshot" style={{ width: '100%', borderRadius: 10, objectFit: 'contain', maxHeight: 200 }} />
                ) : (
                  <div className="ump-list" style={{ background: '#0f172a', height: 180 }}>No screenshot available.</div>
                )}
              </div>
            </div>
          </div>
        </div>

        <div className="panel">
          <h3>MIDI 2.0 Control</h3>
          <div className="split">
            <button className="btn" onClick={sendTestNote}>Send NoteOn</button>
            <button className="btn secondary" onClick={tailUmp}>Refresh UMP Tail</button>
          </div>
          <div className="panel">
            <h3>UMP Console</h3>
            <div className="ump-list">
              {harness.events.length === 0
                ? '[ ] Awaiting UMP traffic…'
                : harness.events.slice(-8).map((e, idx) => (
                    <div key={`${e.ts}-${idx}`}>
                      [{new Date(e.ts).toLocaleTimeString()}] {e.label} → {e.bytes.map((b) => b.toString(16).padStart(2, '0')).join(' ')}
                    </div>
                  ))}
            </div>
          </div>
          <div className="panel">
            <h3>Logs</h3>
            <div className="ump-list log">
              {logs.length === 0 ? 'Waiting for actions…' : logs.slice(-8).map((l, i) => <div key={i}>{l}</div>)}
            </div>
            <div className="ump-list log" style={{ marginTop: 8 }}>
              <strong>UMP Tail</strong>
              <pre style={{ whiteSpace: 'pre-wrap' }}>{tail}</pre>
            </div>
            <div className="split" style={{ marginTop: 8 }}>
              <button className="btn secondary" onClick={toggleInject}>{injectEnabled ? 'Disable midi2.js Inject' : 'Enable midi2.js Inject'}</button>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default App
