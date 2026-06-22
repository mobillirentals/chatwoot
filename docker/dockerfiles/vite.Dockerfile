FROM chatwoot:development

ENV PNPM_HOME="/root/.local/share/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

# Garante que npm e pnpm estejam disponíveis (podem faltar na imagem base compilada em modo production)
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && npm install -g pnpm@10.2.0 \
 && pnpm --version

RUN chmod +x docker/entrypoints/vite.sh

EXPOSE 3036
CMD ["bin/vite", "dev"]
