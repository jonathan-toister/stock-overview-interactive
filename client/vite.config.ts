import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    // Reachable from other devices on the network during development too
    host: true,
    proxy: {
      '/api': 'http://localhost:3000',
    },
  },
})
