import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      '/api/patchbay': {
        target: process.env.PATCHBAY_URL || 'http://127.0.0.1:7090',
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api\/patchbay/, ''),
      },
    },
  },
})

