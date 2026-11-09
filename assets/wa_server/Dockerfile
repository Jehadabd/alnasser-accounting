# خادم واتساب الناصر — لأي منصة تقبل Docker (Koyeb، Fly.io، Railway، أي خادم)
# node:20 الكامل (فيه git: مكتبة libsignal تُنزَّل من GitHub)
FROM node:20
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund
COPY server.js ./
ENV STATE_DIR=/data PORT=8080
VOLUME /data
EXPOSE 8080
CMD ["node", "server.js"]
