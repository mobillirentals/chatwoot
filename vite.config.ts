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
    // "vite" quando o Rails roda em Docker e o Vite também; "host.docker.internal"
    // quando o Rails está em Docker mas o Vite roda nativo no host (setup recomendado
    // no Windows — ver vite: rodar nativo abaixo).
    allowedHosts: ['localhost', 'vite', 'host.docker.internal'],
    // Só ativa polling se CHOKIDAR_USEPOLLING estiver definido (o docker-compose.yaml
    // já seta isso pro serviço `vite`). Bind mount (./:/app) num host Windows não
    // propaga evento de mudança de arquivo de forma confiável pro container — sem
    // polling ali, o HMR não pega nada sem rebuild manual + restart. Rodando nativo
    // (fora do Docker) isso não é necessário: o watch nativo do SO já funciona.
    watch: process.env.CHOKIDAR_USEPOLLING
      ? { usePolling: true, interval: 500 }
      : undefined,
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
