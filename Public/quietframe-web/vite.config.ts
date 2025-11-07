import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5175,
    proxy: {
      // Dev proxy to PublishingFrontend quietframe routes → MVK sidecar
      '/api/qf': {
        target: 'http://127.0.0.1:8085',
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
  base: '',
})

