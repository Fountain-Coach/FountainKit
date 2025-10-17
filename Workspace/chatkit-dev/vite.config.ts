import { defineConfig } from 'vite';

const GATEWAY = process.env.GATEWAY_URL || 'http://127.0.0.1:8010';

export default defineConfig({
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      '/chatkit': {
        target: GATEWAY,
        changeOrigin: true,
        secure: false,
      },
      '/health': {
        target: GATEWAY,
        changeOrigin: true,
        secure: false,
      },
    },
  },
});

