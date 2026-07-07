import { defineConfig } from 'vite';
import ruby from 'vite-plugin-ruby';
import vue from '@vitejs/plugin-vue';
import { aliases, vueOptions } from './vite.shared';
import yaml from '@rollup/plugin-yaml';

export default defineConfig({
  plugins: [ruby(), vue(vueOptions), yaml()],
  server: {
    // Bind em todas as interfaces para funcionar dentro do Docker.
    // O host nos script tags continua sendo "localhost" (definido no vite.json).
    host: '0.0.0.0',
    // Permite que o container "rails" acesse o Vite pelo hostname do Docker.
    allowedHosts: ['localhost', 'vite'],
  },
  css: {
    preprocessorOptions: {
      scss: {
        api: 'modern-compiler',
      },
    },
  },
  resolve: { alias: aliases },
});
