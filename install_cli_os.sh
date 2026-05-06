#!/usr/bin/env bash

# ============================================================
# [수동 실행 절차]
# OS 설치 시 OpenSSH Server를 체크한 후, 터미널에서 다음 명령어들을 순서대로 실행하세요.
# 1. sudo apt update && sudo apt install -y git
# 2. git clone https://github.com/service0427/nmap_mini.git
# 3. cd nmap_mini
# 4. chmod +x install_cli_os.sh
# 5. ./install_cli_os.sh
#
# * 참고: 
# - .ssh 폴더 생성 명령어는 폴더가 없을 때만 생성하는 안전 장치입니다.
# - OpenSSH Server는 OS 설치 단계에서 이미 체크 후 설치되었다고 가정합니다.
# ============================================================

# install_cli_os.sh: Server Initial Setup Script (CUI Ready)

echo "============================================================"
echo "   Server Initial Setup Start"
echo "============================================================"

# 1. SSH 키 설정 (자동 등록)
echo "[*] Configuring SSH Public Keys..."
# .ssh 디렉토리 생성 및 권한 설정
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# 집 SSH 키 등록
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC07UNfs5EPAYS1TSHdoZofg93FFiHzIxmnixPJMFDgaDF6eKfCBrco2t+fxyyKO2IoxrSj79ii+MYaxYV+oPqMoAS5RrUHrVEgeYNxkkvW6LkxdJzUiHZZOesfcV2djnRphPPIEQND0m7b8RacDiH3Cxv6UMZRtWQVi3vxtqF02RikluTux5H6nnzn197wQE7yBs4J55Wuut6lftrE3meHU2i/pnhFOjr0qOuC2GzP3N/aRH3BEeZ78lQbgwFlzvfLsEdF8ebYXVKiT7TAExjWfcicSu+lDBsn50tAY8HsJVD30zKXImSJl5W/A3Nv63/rexaRfI2O5LQpdjx8STsGmtwtuYiHmfH6swy2wEyN5UEvTxF/fuI7EYIoC0ej44paH8mSv73svQUButhcMkI5ZgXgIerWz0gCGXMA1pwjW0oZKPgN9GnhqDKBXYQYjRr3NApjxwTCcJ4jlRH5TrV9+ass96ChSKpCeKg0R1BAKX2HYal08egOoiEBbUkX+yQ+C/BP02iZcGPqX886cmuR2lF97JFpeEdMxEdb6ClBTrdbRlB9PWq5R7erUXS/1YMNTJZHAeoVa5Jr2JW1cZYS424S3i48vjBZyHMF3VCFHQA7B9n1ztOalzyRpRfB8QrpfaItwNnTho28kDW4zaZ/Ugv1zV8/4P+JcvVo9A3EZw== techb@TechB" >> ~/.ssh/authorized_keys

# 가게 SSH 키 등록
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDrHO2J7IvtUvxry/1jZP/eQfC1CTW2fPUd/x/1xq5A0mNqh7jqM6l1B5jySTCekc4PCHMLqcZFFrsQHVhrKaG2S7ZYtlvDFcxSyWxUcxJUoo5WjhQ7L6OJYy9KvrThbgGhfBx9NVmo0lE/GAYw/RL3JpBfb5mdZr8fFlmm6C9nC2yiQtY+NpnmkeoQnCOL/yFi6uFQpTktpaE0J6tR2JPl0yT524q5J3KV5R4/sPFE1kOmq80C/Gafn6tKaxQ2f7VLX/IYhsxXpq2ymT1UYcH+IDsepYEsNYobEklyod1if2ZuEc0Qr6g76GoR7/3e03p/1vaJJ4Tmge+gIVWmymxzmOJpwQEvDxDBkiWstM2oNqSYYcOc1FC97eA+FqrqJrfYM/LlF70kOQ9KaxJVeZ5dNO99pegYk6DA15tHuWe4RnGtS+A5Sd0Y4V9jIwVDp9PS0oWxjHld7dRMVVqiEUUWcc6fv517OjYkLNg4tXoamYAgDZHDQ4Knjn0Ysusl45lD5Uki+kFbe2yZR8Txr/gwoz7UVarLVxpqmIDyUf0/9D5nWUbLpkYKpVpw8RgTc2G7HALfkzQ28SOX3eMxRTxpVUFQTI/4Y2ys5DEDszHJ0knffLRAPHUUq4f7gcJ8PRWfW8Zs/Yf1ZLpEYV1dcVbyR0mYSOKxC/w9X/6tttR3GQ== moon@DESKTOP-OTKATMO" >> ~/.ssh/authorized_keys

# 권한 재설정 및 중복 제거
sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# 3. SSH 데몬 설정 (PubkeyAuthentication 활성화)
echo "[*] Enabling PubkeyAuthentication in sshd_config..."
sudo sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^PubkeyAuthentication no/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# SSH 서비스 재시작 및 방화벽 설정
sudo systemctl enable ssh
sudo systemctl restart ssh
sudo ufw allow ssh
# sudo ufw --force enable # 필요에 따라 방화벽 활성화

# 4. 타임존 설정 (한국 시간)
echo "[*] Setting timezone to Asia/Seoul..."
sudo timedatectl set-timezone Asia/Seoul
date

# 5. 패키지 리스트 업데이트 및 기본 도구 설치
echo "[*] Updating package list & Installing basic tools..."
sudo apt update
sudo apt install -y git screen adb curl wget build-essential cron net-tools

# 6. Python 및 blackboxprotobuf 설치
echo "[*] Installing Python3 and blackboxprotobuf..."
sudo apt install -y python3 python3-pip python3-dev python3-venv
sudo python3 -m pip install --upgrade pip --break-system-packages || sudo python3 -m pip install --upgrade pip
sudo python3 -m pip install blackboxprotobuf --break-system-packages || sudo python3 -m pip install blackboxprotobuf

# 7. Node.js 최신 LTS 버전 설치
echo "[*] Installing Node.js (Latest LTS)..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt install -y nodejs

# 8. PM2 설치 (글로벌)
echo "[*] Installing PM2..."
sudo npm install -g pm2

# 9. 설치 확인
echo "============================================================"
echo "   Installation Summary"
echo "============================================================"
git --version
screen -v
adb --version
python3 --version
node -v
pm2 -v
sudo systemctl status ssh | grep -i active || echo "SSH Service is not running"
echo "Timezone: $(date)"
echo "============================================================"
echo "   OS Setup Complete!"
echo "============================================================"
