#!/usr/bin/env bash
# تثبيت خادم واتساب الناصر على خادم Linux (Oracle Cloud Always Free / أي VPS بـ Ubuntu)
# الاستعمال (داخل مجلد الخادم):   sudo bash install-oracle.sh <API_KEY>
# يثبّت Node 20 وgit وCaddy، ويشغّل الخادم كخدمة تعود وحدها بعد إعادة التشغيل،
# ويعطيه رابط HTTPS مجانياً على sslip.io (شهادة Let's Encrypt تلقائية).
set -euo pipefail
KEY="${1:-}"
if [ ${#KEY} -lt 24 ]; then echo "الاستعمال: sudo bash install-oracle.sh <API_KEY من البرنامج>"; exit 1; fi
if [ "$(id -u)" -ne 0 ]; then echo "شغّله بـ sudo"; exit 1; fi
SRC="$(cd "$(dirname "$0")" && pwd)"
DIR=/opt/alnaser-wa

echo "== 1/5 الحزم"
apt-get update -y
apt-get install -y curl git ca-certificates gnupg debian-keyring debian-archive-keyring apt-transport-https iptables-persistent
if ! command -v node >/dev/null || [ "$(node -v | cut -d. -f1 | tr -d v)" -lt 20 ]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi

echo "== 2/5 ملفات الخادم"
mkdir -p "$DIR"
cp "$SRC/server.js" "$SRC/package.json" "$DIR/"
cd "$DIR"
npm install --omit=dev --no-audit --no-fund
printf 'API_KEY=%s\nPORT=8080\nSTATE_DIR=%s/data\n' "$KEY" "$DIR" > "$DIR/.env"
chmod 600 "$DIR/.env"

echo "== 3/5 الخدمة"
id -u alnaserwa >/dev/null 2>&1 || useradd --system --home "$DIR" --shell /usr/sbin/nologin alnaserwa
mkdir -p "$DIR/data" && chown -R alnaserwa:alnaserwa "$DIR"
cat > /etc/systemd/system/alnaser-wa.service <<UNIT
[Unit]
Description=Alnaser WhatsApp reminder server
After=network-online.target
Wants=network-online.target

[Service]
User=alnaserwa
WorkingDirectory=$DIR
ExecStart=$(command -v node) $DIR/server.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now alnaser-wa

echo "== 4/5 الجدار الناري (80 و443)"
iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT
iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport 443 -j ACCEPT
netfilter-persistent save || true

echo "== 5/5 HTTPS"
IP="$(curl -fsS https://api.ipify.org || curl -fsS https://ifconfig.me)"
HOST="$(echo "$IP" | tr . -).sslip.io"
if ! command -v caddy >/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -y && apt-get install -y caddy
fi
printf '%s {\n  reverse_proxy 127.0.0.1:8080\n}\n' "$HOST" > /etc/caddy/Caddyfile
systemctl restart caddy

echo
echo "✅ تم. رابط الخادم (الصقه في البرنامج):  https://$HOST"
echo "   إن لم يفتح: أضف في Oracle Cloud ← VCN ← Security List قاعدة Ingress للمنفذين 80 و443 من 0.0.0.0/0"
