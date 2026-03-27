#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# DigitalOcean Droplet Setup Script
# Run this ONCE on a fresh Ubuntu 22.04+ droplet.
#
# Usage:
#   ssh root@YOUR_DROPLET_IP
#   bash setup.sh
# ──────────────────────────────────────────────────────────────
set -euo pipefail

APP_DIR="/opt/earthranger"
DOMAIN="${1:-}"  # Pass domain as first arg, e.g. bash setup.sh epictech.com.vn

echo "═══ System update ═══"
apt update && apt upgrade -y
apt install -y python3 python3-venv python3-pip nginx certbot python3-certbot-nginx curl git ufw

echo "═══ Firewall ═══"
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

echo "═══ Create app user ═══"
id -u www-data &>/dev/null || useradd -r -s /bin/false www-data

echo "═══ App directory ═══"
mkdir -p "$APP_DIR"

echo "═══ Python venv ═══"
python3 -m venv "$APP_DIR/venv"
source "$APP_DIR/venv/bin/activate"
pip install --upgrade pip

echo ""
echo "═══ NEXT STEPS ═══"
echo "1. Upload your code:      scp -r v2/* root@DROPLET_IP:$APP_DIR/"
echo "2. Install deps:          cd $APP_DIR && source venv/bin/activate && pip install -r requirements.txt"
echo "3. Create .env:           cp .env.example .env && nano .env   (fill in secrets)"
echo "4. Copy service account:  scp service-account.json root@DROPLET_IP:$APP_DIR/"
echo "5. Install systemd:       cp deploy/earthranger.service /etc/systemd/system/"
echo "                          systemctl daemon-reload && systemctl enable earthranger"
echo "6. Install nginx:         cp deploy/nginx.conf /etc/nginx/sites-available/earthranger"
echo "                          ln -sf /etc/nginx/sites-available/earthranger /etc/nginx/sites-enabled/"
echo "                          rm -f /etc/nginx/sites-enabled/default"
echo "                          nginx -t && systemctl reload nginx"
if [ -n "$DOMAIN" ]; then
    echo "7. SSL (HTTPS):           certbot --nginx -d $DOMAIN"
fi
echo "8. Start:                 systemctl start earthranger"
echo "9. Check:                 systemctl status earthranger"
echo "                          curl http://localhost:8000/health"
echo ""
echo "═══ Done! ═══"
