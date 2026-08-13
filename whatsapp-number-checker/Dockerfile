FROM node:20-alpine

WORKDIR /app

# git: algumas dependencias transitivas do Baileys resolvem via URL de git, nao só do
# registry npm — sem isso o `npm install` falha com ENOENT procurando o binario git.
RUN apk add --no-cache git

COPY package.json ./
RUN npm install --omit=dev

COPY src/ ./src/

EXPOSE 3300

CMD ["node", "src/index.js"]
