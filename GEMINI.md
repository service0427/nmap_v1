# Naver Map Auto-Simulation Single-Mode (V1.0.0)

## 🚀 V1.0.0 Core Architecture (Single-Mode)

V1.0.0은 기존의 복잡한 멀티 인스턴스 의존성을 제거하고, 각 기기가 독립적인 고성능 오케스트레이션을 수행하는 "Single-Mode" 완전 무인 시스템입니다.

### 🛠 핵심 운영 원칙
*   **Decentralized Orchestration**: 모든 기기는 `wifi_single/` 하위의 독립적인 스케줄러와 패킷 검증 엔진을 통해 주행을 수행합니다.
*   **Pure Dynamic UI**: 실시간 XML 덤프 분석을 통해 UI를 조작하며, 하드코딩된 좌표를 절대 사용하지 않습니다.
*   **Atomic Packet Verification**: 앱의 서버 보고 패킷을 실시간 가로채어 액션의 성공 여부를 원자 단위로 판정합니다.
*   **Randomized IP Rotation**: LTE 동글의 IP를 120~180분 사이의 랜덤 주기로 자동 회전시켜 네트워크 탐지를 회피합니다.
*   **Self-Healing Connectivity**: 인터넷 단절 시 USB 리셋(Unbind/Bind) 및 Surgical 라우팅 복구를 자동으로 수행합니다.

### 📂 Directory Structure
*   `wifi_single/`: V1.0.0 메인 엔진 및 싱글모드 오케스트레이터.
    *   `loop.sh`: 실시간 작업 할당 및 안전 감시자.
    *   `lib/main.sh`: 패킷 기반 주행 제어 핵심 로직.
    *   `logs/{DEV_ID}/.../`: 세션별 격리된 로그, 패킷 데이터, 스크린샷 저장.
*   `utils/`: 공용 유틸리티 및 네트워크 관리 도구.
    *   `lte_ip_rotator.py`: 랜덤 IP 회전 및 연결 상태 감시 대몬.
    *   `web_monitor.py`: 통합 웹 모니터링 서버.

## 🛡️ Safety & Reliability

### 1. Global Session Timeout (15-Min Rule)
*   세션 시작 후 **15분** 경과 시, 스크립트 프로세스뿐만 아니라 안드로이드 앱 패키지까지 강제 종료(`am force-stop`)하여 좀비 세션을 차단합니다.

### 2. Ghost App & Stale Session Detection
*   **Ghost App**: 프로세스는 없으나 앱이 떠 있는 경우 감지하여 즉시 정리.
*   **Stale Session**: 하트비트(Lock 파일) 갱신이 60초 이상 지연되면 실패로 간주하고 복구 모드 진입.

### 3. LTE Modem Auto-Doctor
*   `loop.sh` 및 `lte_ip_rotator.py`가 주기적으로 모뎀의 상태를 체크하여, 이름(lte11~) 및 라우팅 테이블(Table 111~)이 꼬여있을 경우 즉시 정상화합니다.

### 4. PM2 Service Lifecycle
*   모든 핵심 서비스(`lte-ip-rotator`, `nmap-monitor`, `lte-usage-sender`)는 PM2를 통해 관리되며, `wifi-scheduler`는 필요 시 수동 기동하는 OFF 방식을 기본으로 합니다.

## 🔧 CLI Utilities (cmd.sh)

*   **`--light`**: 화면 밝기, 볼륨, 애니메이션 배율 기본값 복구 및 방해 금지 모드 해제.
*   **`--reboot`**: 연결된 모든 기기 일괄 재부팅.
*   **`--ip`**: 비행기 모드 토글을 통한 수동 IP 갱신.
*   **`--wifi`**: 주변 Moon/U26 와이파이 자동 선택 연결 및 연결 확인 팝업 자동 해결.
