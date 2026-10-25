# Flow Music 🎵 (iOS & Android)

แอพพลิเคชันฟังเพลงไร้โฆษณา 100% เชื่อมต่อกับ YouTube Music ผ่านการทำ Reverse Engineering (REA) สำหรับ InnerTube API และ JavaScript Player Cipher รองรับทั้ง iOS และ Android อย่างสมบูรณ์แบบ

---

## ✨ ไฮไลต์ฟีเจอร์เด่น (Key Features)

- 🚫 **ไม่มีโฆษณาคั่น (100% Ad-Free)**: สตรีมเสียงตรงจาก Google Video CDN โดยไม่ต้องโหลดหรือแสดงโฆษณา
- ⚡ **REA Cipher Engine**: ถอดรหัสลายเซ็น (`s`) และแก้อาการสปีดตกจาก Throttling (`n-sig`) ผ่าน Embedded QuickJS Engine ภายในตัวแอพ
- 📱 **เล่นเพลงเบื้องหลัง (Background Playback)**: เล่นเพลงต่อเนื่องแม้ล็อคหน้าจอ หรือสลับไปใช้แอพอื่น พร้อมหน้าต่างควบคุมบน Lock Screen & Control Center
- 🎼 **เนื้อเพลงวิ่งตามจังหวะ (Time-Synced Lyrics)**: ดึงเนื้อเพลงแบบ Timestamped LRC ผ่าน LRCLIB อัตโนมัติ
- 📻 **วิทยุต่อเนื่องอัตโนมัติ (Endless Radio)**: เมื่อเล่นเพลงจบ แอพจะดึงเพลงที่คล้ายกันมาเล่นต่ออัตโนมัติ
- 📥 **ดาวน์โหลดฟังออฟไลน์ (Offline Mode)**: ดาวน์โหลดเพลงเก็บไว้ในเครื่องเพื่อฟังตอนไม่มีอินเทอร์เน็ต
- 🎨 **Modern Dark Glassmorphism UI**: ดีไซน์หรูหราทันสมัย พื้นหลังเบลอตามสีของปกอัลบั้ม พร้อม Mini-Player ที่ย่อ/ขยายได้

---

## 🛠️ สถาปัตยกรรมและการทำงานของ REA Engine

```
[Flutter UI] 
      │
      ▼
[InnerTube Client] ──▶ POST music.youtube.com/youtubei/v1/player
      │
      ▼
[Cipher Resolver] ──▶ ดาวน์โหลด player.js และรัน deobfuscate ผ่าน Embedded QuickJS
      │
      ▼
[just_audio Engine] ◀── สตรีมเสียงระดับ Full-speed จาก CDN
```

1. **InnerTube Client**: จำลอง Header และ Context เป็น `WEB_REMIX` สื่อสารผ่าน REST API ของ YouTube Music
2. **CipherResolver**: แกะ JavaScript จาก `base.js` ของ YouTube เพื่อดึง Logic การถอดรหัส Token และ n-parameter
3. **Audio Pipeline**: ใช้ `just_audio` และ `audio_service` เพื่อรองรับ Foreground Service บน Android และ `MPRemoteCommandCenter` บน iOS

---

## 🚀 การติดตั้งและนำไปใช้งาน (Deployment)

### 🤖 สำหรับ Android:
1. ดาวน์โหลดไฟล์ `.apk` จากแท็บ **Releases** หรือผ่าน **GitHub Actions Artifacts**
2. ติดตั้งลงในเครื่อง Android และเปิดใช้งานได้ทันที

### 🍎 สำหรับ iOS (Sideloading):
เนื่องจากแอพประเภทนี้ไม่สามารถขึ้น App Store ได้อย่างเป็นทางการ จึงปล่อยเป็นไฟล์ `.ipa` สำหรับ Sideload:
1. ดาวน์โหลดไฟล์ `FlowMusic-iOS.ipa` จาก GitHub Actions Artifacts
2. ติดตั้งผ่านหนึ่งในเครื่องมือเหล่านี้:
   - **AltStore / SideStore**: ติดตั้งผ่านคอมพิวเตอร์หรือ Wi-Fi (ฟรี)
   - **TrollStore**: สำหรับ iOS เวอร์ชันที่รองรับ CoreTrust Bug (ติดตั้งถาวรไม่ต้องรีเซ็น)
   - **Scarlet / Feather / Sideloadly**: ติดตั้งผ่าน Certificate ส่วนตัว

---

## 💻 การรันโปรเจกต์ในเครื่อง Local (Development)

```bash
# 1. ดึง dependencies
flutter pub get

# 2. รันบนเครื่องจริงหรือ Simulator
flutter run

# 3. Build Release สำหรับ Android
flutter build apk --release

# 4. Build Release สำหรับ iOS (Unsigned)
flutter build ios --release --no-codesign
```
