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

## 4. 3단계: 네트워크 프록시 및 Frida 후킹 기반 실행

네이버 지도는 단순 앱 실행 시 자체적인 보안 로직과 SSL Pinning 방어 기제 때문에 일반적인 환경(그냥 Wi-Fi에 프록시만 잡고 켤 경우)에서는 무조건 **"네트워크 차단"** 또는 무한 로딩이 발생합니다.

반드시 **V2 시스템의 스크립트(`test_nmap_v2/run_single.sh` 또는 `lib/main.sh` 등)를 통해 앱을 실행**해야 합니다.

**해당 스크립트들이 앱을 실행할 때 백그라운드에서 해주는 필수 작업들:**
1.  **동적 프록시 할당**: `adb shell settings put global http_proxy localhost:MITM_PORT` 명령으로 통신을 Mitmproxy로 넘김.
2.  **Frida Spawn 실행**: 앱을 단순히 터치해서 켜는 것이 아니라, Frida를 이용해 `_core_survival.js` 와 `network_hook.js` 스크립트를 주입(Inject)하면서 동시에 실행(Spawn)시킵니다.
    *   *이 과정이 누락되면 앱 내의 통신 보안 모듈이 우회되지 않아 네트워크 차단이 발생합니다.*

---

## 💡 요약: 트러블슈팅 체크리스트

신규 기기에서 네트워크가 차단될 때 확인해야 할 3가지:

1.  **Magisk 모듈이 활성화되어 있는가?**
    *   Magisk 앱에서 Frida-Server(17.7.3)와 AlwaysTrustUserCerts가 '활성화' 상태인지 확인하세요.
2.  **시스템 인증서가 올바르게 주입되었는가?**
    *   기기 설정 -> 보안 -> 암호화 및 사용자 증명 -> '신뢰할 수 있는 자격증명(시스템)' 목록 하단에 `mitmproxy`가 있는지 확인하세요.
3.  **앱을 런처에서 손으로 직접 켰는가?**
    *   절대 손으로 켜지 마세요. 제어 서버의 V2 실행 스크립트(`run_single.sh` 등)를 통해서만 구동해야 생존용(Survival) Frida 후킹이 주입되어 네트워크 차단을 방지합니다.
