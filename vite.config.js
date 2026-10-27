import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// This site is published from the /KingTrader/ GitHub Pages project path.
export default defineConfig({
  plugins: [react()],
  base: '/KingTrader/',
});
