import { defineConfig } from 'vite'

export default defineConfig({
  server: {
    proxy: {
      '/v1/snapshot': {
        target: process.env.VITE_SEMANTIC_BROWSER_URL || 'http://127.0.0.1:8007',
        changeOrigin: true
      },
      '/ump': {
        target: process.env.VITE_MIDI_SERVICE_URL || 'http://127.0.0.1:7180',
        changeOrigin: true
      }
    }
  }
})
