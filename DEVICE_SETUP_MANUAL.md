# Naver Map V2 - 신규 기기 및 서버 환경 설정 메뉴얼

본 문서는 신규 단말기 추가 시 **"앱 실행 후 네트워크 차단"** 문제가 발생하는 것을 방지하고, 정상 동작 중인 서버와 기기들의 설정 상태를 완벽히 일치시키기 위한 가이드입니다. 

네트워크 차단(Network Block/SSL Error)은 주로 **인증서 신뢰 문제, Frida 탐지 우회 실패, 또는 Magisk 모듈 미설치**로 인해 발생합니다.

---

## 1. 운영 서버 (제어 서버) 환경 스펙

현재 정상 구동 중인 `U22-01` 제어 서버의 핵심 소프트웨어 버전입니다. 새로운 서버를 구축하거나 이관할 때 다음 버전을 일치시키는 것을 권장합니다.

*   **OS**: Ubuntu 22.04.1 LTS (Kernel: 6.8.0-90-generic)
*   **Python**: 3.13.9
*   **Mitmproxy**: 12.2.2
*   **Frida (Host)**: 17.9.1
*   **ADB/Fastboot**: 최신 버전 유지 권장

---

## 2. 1단계: 자동화 스크립트 실행 (`install_devices.sh`)

`/home/tech/nmap/install_devices.sh` 스크립트는 초기 세팅을 자동화합니다. 해당 서버(제어 서버)에 기기를 USB 디버깅 상태로 연결하고 실행합니다.

**스크립트가 수행하는 작업:**
1.  **앱 설치**: `com.nhn.android.nmap` (6.5.2.1 버전 Base + Splits) 및 GPS 에뮬레이터 설치.
2.  **인증서 주입**: 서버의 실제 작동 중인 인증서(`~/.mitmproxy/mitmproxy-ca-cert.pem`)를 기기의 유저 인증서 저장소(`/data/misc/user/0/cacerts-added/`)에 주입합니다. 
    *   **⚠️[중요] 좀비 인증서 색출 기능 탑재**: 과거 `trustusercerts` 등 다른 Magisk 모듈에 의해 낡은 가짜 인증서가 캐싱되어 무한 복구되는 치명적인 버그(SSL 에러의 주범)가 있었습니다. 현재 스크립트는 이를 방지하기 위해 기기 전체(`/data` 내부)를 스캔하여 숨어있는 모든 가짜 인증서를 현재 활성화된 진짜 인증서로 강제 덮어씌웁니다.
3.  **시스템 환경 최적화**: 
    *   안드로이드 기본 WebView (`com.google.android.webview`) 비활성화/다운그레이드 (크롬 기반 웹뷰 충돌 방지)
    *   Google Play Store (`com.android.vending`) 자동 업데이트 차단을 위해 비활성화
    *   자동 회전 및 OTA 시스템 업데이트 비활성화
4.  **Magisk 모듈 파일 복사**: `/sdcard/Download/` 폴더로 필수 Zip 파일들을 복사 (설치 아님).

---

## 3. 2단계: ⚠️ [핵심] Magisk 모듈 수동 설치

스크립트는 파일을 복사할 뿐, 안드로이드 권한 구조상 **Magisk 모듈을 자동으로 설치하지 못합니다.** 기기 앱 실행 후 네트워크가 차단되었다면 이 과정을 누락했을 확률이 가장 높습니다.

기기 화면에서 직접 다음 작업을 수행해야 합니다:

1.  **Magisk 앱 실행** -> 하단 **모듈(Modules)** 탭 이동
2.  **"저장소에서 설치(Install from storage)"** 선택
3.  `/sdcard/Download/` 경로에 있는 다음 3개의 파일을 각각 선택하여 설치:
    *   `MagiskFrida-17.7.3.zip` : 기기 내에서 Frida-Server를 Root 권한으로 자동 실행 (네트워크/탐지 우회 후킹을 위해 필수)
    *   `AlwaysTrustUserCerts.zip` : 앱이 시스템/유저 인증서를 강제로 신뢰하도록 설정 (SSL Pinning 이슈 해소)
    *   `LSPosed.zip` : 필수 Xposed 프레임워크 환경 제공
4.  모든 모듈 설치가 완료되면 **기기를 반드시 재부팅(Reboot)** 합니다.

---

## 4. 3단계: USB 안정성 및 MTP 차단 설정 (매우 중요 ⭐️)

여러 대의 기기를 연결할 때 발생하는 **USB 미세 끊김(Bus Reset)**을 방지하기 위해 다음 설정을 반드시 확인합니다.

1.  **MTP 완전 차단**: `install_devices.sh` 실행 시 자동으로 처리되지만, 수동 확인이 필요할 경우 기기 상단 바를 내려 USB 모드를 **'휴대전화 충전만(Charging Only)'**으로 변경합니다.
2.  **워치독 작동 확인**: V2 엔진(`main.sh`)에는 터널 단절 시 **1초 내로 복구**하는 워치독이 포함되어 있습니다. 실행 로그(`execution.log`)에 `[⚠️] Tunnel lost! Restoring...` 메시지가 뜨더라도 주행이 멈추지 않는다면 정상입니다.

## 5. 4단계: NLOG 패킷 수집 및 HostnameVerifier 우회

네이버 지도의 분석 로그(NLOG) 수집을 위해 `network_hook.js`에 **HostnameVerifier 우회 로직**이 포함되어 있습니다.

*   **기능**: 인증서의 호스트 이름 불일치를 무시하여 `nlogapp` 패킷을 강제로 Mitmproxy로 끌어옵니다.
*   **확인**: `logs/.../mitm.log` 또는 `.json` 파일 목록에 `019_POST_nlogapp.json` 등이 생성되는지 확인하세요.

---

## 💡 요약: 트러블슈팅 체크리스트

신규 기기에서 네트워크가 차단되거나 패킷이 안 쌓일 때 확인해야 할 4가지:

1.  **Magisk 모듈이 활성화되어 있는가?**
    *   `magisk --install-module` 명령으로 자동 설치되지만, 기기 재부팅 후 Magisk 앱에서 '활성화' 상태인지 꼭 확인하세요.
2.  **USB 모드가 '충전 전용'인가?**
    *   MTP가 켜져 있으면 데이터 전송 대역폭 문제로 터널이 자주 끊길 수 있습니다.
3.  **인증서가 시스템 단에 주입되었는가?**
    *   `mitmproxy` 인증서가 시스템 자격증명 목록에 있어야 NLOG 네이티브 통신이 뚫립니다.
4.  **최신 Frida 후킹 스크립트인가?**
    *   `HostnameVerifier.verify.implementation = function(...) { return true; }` 코드가 `network_hook.js`에 있는지 확인하세요.
