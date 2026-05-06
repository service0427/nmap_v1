# Nmap Web Monitor 설치 및 실행 매뉴얼 (Ubuntu 26 기준)

이 문서는 오리지널 서버(Ubuntu 26 등 최신 Linux 환경)에서 `nmap-monitor` (웹 브라우저 기반 다중 기기 실시간 모니터링 & 조작 툴)를 처음부터 세팅하고 PM2로 백그라운드 구동하는 과정을 안내합니다.

## 1. 필수 시스템 패키지 설치

스크립트는 내부적으로 `adb`를 통한 기기 제어와 `ffmpeg`를 통한 실시간 고프레임 화면 스트리밍(MJPEG)을 사용하므로 해당 시스템 유틸리티가 반드시 설치되어 있어야 합니다.

```bash
sudo apt update
sudo apt install -y android-tools-adb ffmpeg python3 python3-pip
```

## 2. Python 라이브러리 설치

웹 서버 구동을 위해 `flask` 라이브러리가 필요합니다. Ubuntu 26과 같은 최신 데비안 기반 시스템에서는 전역 설치 시 PEP 668 정책으로 인해 에러가 발생하므로, `--break-system-packages` 플래그를 사용하거나 시스템 패키지 관리자를 통해 설치해야 합니다.

```bash
# Flask 전역 설치
pip3 install flask --break-system-packages
```
*(선택 사항: `sudo apt install python3-flask` 명령어를 통해 설치하셔도 무방합니다.)*

## 3. Node.js 및 PM2 설치

백그라운드에서 스크립트를 안정적으로 무한 실행하고 관리하기 위해 Node.js 환경의 `pm2` 매니저를 사용합니다.

```bash
# Node.js 최신 LTS 설치 (기존에 설치되어 있다면 생략)
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs

# PM2 전역 설치
sudo npm install -g pm2
```

## 4. PM2로 웹 모니터 구동하기

모든 준비가 완료되었습니다. `pm2`를 사용하여 파이썬 스크립트를 프로세스로 등록하고 실행합니다.

```bash
# Nmap 프로젝트 디렉토리로 이동
cd /home/tech/nmap

# PM2에 nmap-monitor 이름으로 파이썬 스크립트 등록 및 실행
pm2 start utils/web_monitor.py --name "nmap-monitor" --interpreter python3

# 서버 재부팅 시에도 자동으로 PM2가 켜지도록 설정 (선택 사항)
pm2 startup
pm2 save
```

## 5. 실행 확인 및 접속

PM2 목록에서 상태를 확인합니다.
```bash
pm2 list
pm2 logs nmap-monitor
```

브라우저를 열고 다음 주소로 접속하면 실시간 다중 폰 모니터링 및 터치 제어 화면을 보실 수 있습니다.
* **접속 주소:** `http://<서버_IP_주소>:5000`

---
> **💡 TIP:**
> * **장치 연결 확인:** 웹 모니터에서 화면이 나오지 않을 경우 서버 터미널에서 `adb devices`를 입력하여 폰들이 `device` 상태로 올바르게 인식되고 있는지 확인하세요.
> * **성능 최적화:** `web_monitor.py`는 `screenrecord`와 파이프를 이용해 초당 30프레임 이상의 부드러운 MJPEG 화면을 송출합니다. 동시에 여러 대를 띄울 경우 네트워크 대역폭(포트 5000번)이 충분히 확보되어야 합니다.
