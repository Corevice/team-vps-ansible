#!/bin/bash
# step-ca initial bootstrap (F6: 自己運用 PKI)
#
# 前提:
#   - Purple Codens AWS の小さい VPS を 1 台用意 (step-ca.internal.corevice)
#   - その VPS に root SSH できる状態
#
# 実行:
#   ssh root@step-ca.internal.corevice
#   bash pki-bootstrap.sh

set -euo pipefail

STEP_CA_VERSION="0.27.0"
STEP_CA_HOME="/opt/step-ca"

apt-get update
apt-get install -y wget

# step-ca install
cd /tmp
wget "https://dl.smallstep.com/cli/docs-cli-install/latest/step-cli_amd64.deb"
wget "https://dl.smallstep.com/certificates/docs-ca-install/latest/step-ca_amd64.deb"
dpkg -i step-cli_amd64.deb step-ca_amd64.deb

# step-ca user + dir
useradd -r -m -d /etc/step-ca -s /bin/false step-ca || true
mkdir -p $STEP_CA_HOME
chown -R step-ca:step-ca $STEP_CA_HOME

# CA initialize
sudo -u step-ca STEPPATH=$STEP_CA_HOME step ca init \
  --name "Codens VPS PKI" \
  --dns "step-ca.internal.corevice,localhost" \
  --address ":8443" \
  --provisioner admin@corevice.com \
  --remote-management

# JWK provisioner for Ansible bootstrap
sudo -u step-ca STEPPATH=$STEP_CA_HOME step ca provisioner add ansible-bootstrap \
  --type JWK --create

# systemd unit
cat > /etc/systemd/system/step-ca.service <<EOF
[Unit]
Description=step-ca
After=network.target

[Service]
Type=simple
User=step-ca
Group=step-ca
Environment=STEPPATH=$STEP_CA_HOME
ExecStart=/usr/bin/step-ca $STEP_CA_HOME/config/ca.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now step-ca

# Output: root cert と fingerprint
echo "=== step-ca root cert (copy to terraform/aws/scripts/step-ca-root.crt) ==="
cat $STEP_CA_HOME/certs/root_ca.crt

echo "=== step-ca fingerprint (paste into group_vars/all.yml step_ca_fingerprint) ==="
sudo -u step-ca STEPPATH=$STEP_CA_HOME step certificate fingerprint $STEP_CA_HOME/certs/root_ca.crt
