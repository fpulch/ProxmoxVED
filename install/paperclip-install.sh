#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Fabian Pulch (fpulch)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/paperclipai/paperclip

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  git \
  python3 \
  ripgrep
msg_ok "Installed Dependencies"

NODE_VERSION="24" NODE_MODULE="pnpm" setup_nodejs
PG_VERSION="17" setup_postgresql
PG_DB_NAME="paperclip" PG_DB_USER="paperclip" setup_postgresql_db

fetch_and_deploy_gh_release "paperclip" "paperclipai/paperclip" "tarball"

msg_info "Building Paperclip"
cd /opt/paperclip
export HUSKY=0
export NODE_OPTIONS="--max-old-space-size=8192"
$STD pnpm install --frozen-lockfile
$STD pnpm build
unset NODE_OPTIONS
msg_ok "Built Paperclip"

msg_info "Installing Agent CLIs"
$STD npm install -g \
  @anthropic-ai/claude-code@latest \
  @openai/codex@latest
msg_ok "Installed Agent CLIs"

msg_info "Configuring Paperclip"
mkdir -p /opt/paperclip-data
mkdir -p /root/.claude /root/.codex
BETTER_AUTH_SECRET=$(openssl rand -hex 32)
cat <<EOF >/opt/paperclip/.env
DATABASE_URL=postgresql://${PG_DB_USER}:${PG_DB_PASS}@127.0.0.1:5432/${PG_DB_NAME}
HOST=0.0.0.0
PORT=3100
SERVE_UI=true
PAPERCLIP_HOME=/opt/paperclip-data
PAPERCLIP_INSTANCE_ID=default
PAPERCLIP_DEPLOYMENT_MODE=authenticated
PAPERCLIP_DEPLOYMENT_EXPOSURE=private
PAPERCLIP_PUBLIC_URL=http://${LOCAL_IP}:3100
BETTER_AUTH_SECRET=${BETTER_AUTH_SECRET}
EOF
msg_ok "Configured Paperclip"

msg_info "Running Database Migrations"
set -a && source /opt/paperclip/.env && set +a
$STD pnpm db:migrate
msg_ok "Ran Database Migrations"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/paperclip.service
[Unit]
Description=Paperclip
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/paperclip
EnvironmentFile=/opt/paperclip/.env
Environment=HOME=/root
Environment=CODEX_HOME=/root/.codex
Environment=PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin
Environment=DISABLE_AUTOUPDATER=1
ExecStart=/usr/bin/node --import /opt/paperclip/server/node_modules/tsx/dist/loader.mjs /opt/paperclip/server/dist/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now paperclip
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
