# แก้ไขปัญหา Flutter Windows - Symlink Support

## 🔴 Error ที่พบ

```
Error: Building with plugins requires symlink support.
Please enable Developer Mode in your system settings.
```

## 📖 อธิบายปัญหา

### Symlink คืออะไร?
- **Symbolic Link (Symlink)** = ทางลัดที่ชี้ไปที่ไฟล์หรือโฟลเดอร์อื่น
- Flutter ใช้ symlink เพื่อเชื่อมต่อ plugin dependencies เข้ากับโปรเจกต์

### ทำไม Windows ต้องการ Developer Mode?
- Windows มีข้อจำกัดด้านความปลอดภัย
- การสร้าง symlink ต้องการสิทธิ์พิเศษ
- Developer Mode เปิดให้ developers สร้าง symlink ได้โดยไม่ต้องเป็น Administrator

---

## ✅ วิธีแก้ไข

### วิธีที่ 1: เปิด Developer Mode (แนะนำ)

#### ขั้นตอน:

1. **เปิด Windows Settings**
   
   **วิธีที่ 1: ใช้คำสั่ง (เร็วที่สุด)**
   ```powershell
   start ms-settings:developers
   ```
   
   **วิธีที่ 2: เปิดด้วยมือ**
   - กด `Windows + I` เพื่อเปิด Settings
   - ไปที่ **Update & Security** → **For developers**
   - หรือค้นหา "Developer Mode" ในช่องค้นหา

2. **เปิดใช้งาน Developer Mode**
   - เลื่อนหาส่วน **"Developer Mode"**
   - เปิดสวิตช์ **"Developer Mode"**
   - จะมี popup แจ้งเตือน → คลิก **"Yes"**

3. **รอให้ Windows ตั้งค่าเสร็จ** (อาจใช้เวลา 1-2 นาที)

4. **ปิดและเปิด Terminal/PowerShell ใหม่**

5. **ลองรัน Flutter อีกครั้ง**
   ```powershell
   cd frontend
   flutter pub get
   flutter run
   ```

---

### วิธีที่ 2: ใช้ Administrator (ไม่แนะนำ)

ถ้าไม่ต้องการเปิด Developer Mode สามารถรัน Flutter ด้วยสิทธิ์ Administrator:

1. คลิกขวาที่ PowerShell → **Run as Administrator**
2. รันคำสั่ง Flutter ตามปกติ

⚠️ **ข้อเสีย:** ต้องรัน Terminal แบบ Administrator ทุกครั้ง

---

## 🔍 ตรวจสอบว่าเปิดใช้งานแล้วหรือยัง

### วิธีที่ 1: ตรวจสอบใน Settings
```powershell
start ms-settings:developers
```
ดูว่าสวิตช์ "Developer Mode" เป็น **On** หรือไม่

### วิธีที่ 2: ตรวจสอบผ่าน Registry (ขั้นสูง)
```powershell
Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue
```
ถ้าแสดง `1` แสดงว่าเปิดใช้งานแล้ว

---

## ⚠️ ข้อควรระวัง

### ความปลอดภัย
- Developer Mode เปิดให้มีสิทธิ์มากขึ้น
- ควรเปิดเฉพาะเมื่อพัฒนาแอป
- สามารถปิดได้เมื่อไม่ใช้แล้ว

### ระบบไฟล์
- **NTFS** - รองรับ symlink ✅
- **exFAT** - ไม่รองรับ symlink ❌
- ตรวจสอบด้วย:
  ```powershell
  fsutil fsinfo volumeinfo C:
  ```

---

## 🐛 แก้ไขปัญหาอื่นๆ

### ปัญหา: เปิด Developer Mode แล้วยังไม่ได้

**ตรวจสอบ:**
1. รีสตาร์ท Terminal/PowerShell
2. รีสตาร์ทคอมพิวเตอร์ (บางครั้งต้องทำ)
3. ตรวจสอบว่าเป็น NTFS file system

### ปัญหา: ไม่สามารถเปิด Developer Mode ได้

**ตรวจสอบ:**
- ต้องเป็น Windows 10/11
- ต้องเป็น Windows Home หรือสูงกว่า
- ลองอัปเดต Windows

---

## 📝 สรุปคำสั่ง

```powershell
# 1. เปิด Developer Mode settings
start ms-settings:developers

# 2. หลังจากเปิดแล้ว - รีสตาร์ท Terminal

# 3. ลองรัน Flutter
cd frontend
flutter clean
flutter pub get
flutter run
```

---

## 📚 อ้างอิง

- [Flutter Windows Setup](https://docs.flutter.dev/get-started/install/windows)
- [Windows Developer Mode](https://docs.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development)

