# خادم واتساب الناصر — لأي منصة تقبل Docker (Render، Koyeb، Fly.io، Railway، أي خادم)
# مرحلتان: التثبيت في node:20 الكامل (فيه git: مكتبة libsignal تُنزَّل من GitHub)،
# والتشغيل في node:20-slim الأصغر (يستيقظ أسرع على المنصات المجانية).
FROM node:20 AS build
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund

FROM node:20-slim
WORKDIR /app
COPY --from=build /app/node_modules ./node_modules
COPY package.json server.js ./
ENV NODE_ENV=production STATE_DIR=/data PORT=8080
RUN mkdir -p /data && chown node:node /data
USER node
VOLUME /data
EXPOSE 8080
CMD ["node", "server.js"]
