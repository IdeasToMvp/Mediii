# Build from repo root via Railway: dockerfilePath = backend/Dockerfile
# Railway uses this directory as the build context.

FROM node:22-alpine
WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY . .

ENV NODE_ENV=production

CMD ["npm", "start"]
