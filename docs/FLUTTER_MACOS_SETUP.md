# Flutter Setup สำหรับ macOS

## 🍎 macOS vs Windows - ความแตกต่าง

### บน macOS:
- ✅ **ไม่ต้องเปิด Developer Mode** - macOS รองรับ symlink โดยปกติ
- ✅ รองรับ symlink แบบ native
- ⚠️ แต่ต้องติดตั้ง **Xcode** และ **Command Line Tools**

### บน Windows:
- ❌ ต้องเปิด **Developer Mode** สำหรับ symlink support
- ❌ Windows จำกัดการสร้าง symlink

---

## 📋 Prerequisites สำหรับ macOS

### 1. Xcode Command Line Tools (จำเป็น)

```bash
# ตรวจสอบว่าติดตั้งแล้วหรือยัง
xcode-select -p

# ถ้ายังไม่ติดตั้ง - ติดตั้งด้วยคำสั่งนี้
xcode-select --install
```

จะเปิดหน้าต่างให้ยอมรับ license และดาวน์โหลด (~500MB)

### 2. Xcode (สำหรับพัฒนา iOS/macOS apps)

- เปิด **Mac App Store**
- ค้นหา "Xcode"
- ดาวน์โหลดและติดตั้ง (ขนาดใหญ่ ~10-15GB)

หลังจากติดตั้งแล้ว:

```bash
# ยอมรับ Xcode license
sudo xcodebuild -license accept

# ตั้งค่า path
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

### 3. Homebrew (แนะนำ - package manager)

```bash
# ติดตั้ง Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 4. CocoaPods (สำหรับ iOS/macOS development)

```bash
# ติดตั้งผ่าน gem
sudo gem install cocoapods
```

---

## 🚀 ติดตั้ง Flutter บน macOS

### วิธีที่ 1: ใช้ Homebrew (แนะนำ)

```bash
# ติดตั้ง Flutter
brew install --cask flutter

# ตรวจสอบ installation
flutter doctor
```

### วิธีที่ 2: ดาวน์โหลดแบบ Manual

```bash
# ดาวน์โหลด Flutter SDK
cd ~/development
git clone https://github.com/flutter/flutter.git -b stable

# เพิ่ม Flutter เข้า PATH
echo 'export PATH="$PATH:$HOME/development/flutter/bin"' >> ~/.zshrc
source ~/.zshrc

# ตรวจสอบ installation
flutter doctor
```

---

## 🔧 ตั้งค่า Environment

### เพิ่ม Flutter เข้า PATH

ถ้าใช้ **Zsh** (macOS Catalina ขึ้นไป):
```bash
echo 'export PATH="$PATH:$HOME/development/flutter/bin"' >> ~/.zshrc
source ~/.zshrc
```

ถ้าใช้ **Bash**:
```bash
echo 'export PATH="$PATH:$HOME/development/flutter/bin"' >> ~/.bash_profile
source ~/.bash_profile
```

---

## ✅ ตรวจสอบการติดตั้ง

```bash
flutter doctor
```

ควรเห็นผลลัพธ์แบบนี้:
```
[✓] Flutter (Channel stable, ...)
[✓] Android toolchain - develop for Android devices
[✓] Xcode - develop for iOS and macOS
[✓] Chrome - develop for the web
[✓] Android Studio
[✓] VS Code
[✓] Connected device
```

---

## 🎯 สำหรับ Apple Silicon (M1/M2/M3)

### ติดตั้ง Rosetta 2 (ถ้าจำเป็น)

```bash
softwareupdate --install-rosetta --agree-to-license
```

### CocoaPods บน Apple Silicon

```bash
# ถ้าเจอปัญหา ffi
sudo gem uninstall ffi
sudo gem install ffi -- --enable-libffi-alloc
```

---

## 📝 รัน Flutter Project บน macOS

### รัน Desktop App

```bash
cd frontend
flutter pub get
flutter run -d macos
```

### รัน iOS Simulator

```bash
# เปิด iOS Simulator
open -a Simulator

# รัน app
flutter run
```

### รัน Android

```bash
flutter run -d android
```

---

## 🐛 แก้ไขปัญหาที่พบบ่อย

### ปัญหา: "xcrun: error: unable to find utility"

**แก้ไข:**
```bash
sudo xcode-select --reset
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

### ปัญหา: CocoaPods errors

**แก้ไข:**
```bash
cd frontend/ios  # หรือ frontend/macos
pod deintegrate
pod install
```

### ปัญหา: Permission denied

**แก้ไข:**
```bash
sudo chown -R $(whoami) /usr/local
```

---

## 📚 คำสั่งที่ใช้บ่อย

```bash
# ตรวจสอบ Flutter
flutter doctor
flutter doctor -v

# อัปเดต Flutter
flutter upgrade

# ตรวจสอบ devices
flutter devices

# รัน app
flutter run

# Build release
flutter build macos
flutter build ios
```

---

## 🔍 สรุปความแตกต่าง

| Platform | Developer Mode | Symlink Support | Notes |
|----------|---------------|-----------------|-------|
| **Windows** | ✅ ต้องเปิด | ❌ ต้อง Developer Mode | ต้องตั้งค่าเพิ่ม |
| **macOS** | ❌ ไม่ต้อง | ✅ รองรับ native | ต้องมี Xcode |
| **Linux** | ❌ ไม่ต้อง | ✅ รองรับ native | ไม่ต้องตั้งค่าพิเศษ |

---

## 📖 อ้างอิง

- [Flutter macOS Setup](https://docs.flutter.dev/get-started/install/macos)
- [Xcode Installation](https://developer.apple.com/xcode/)
- [Homebrew](https://brew.sh/)

