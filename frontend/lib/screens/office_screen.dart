import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/screens/home_screen.dart';

class OfficeScreen extends StatelessWidget {
  const OfficeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    // ถ้าไม่ใช่ admin ห้ามเข้า ให้เด้งกลับ /home ทันที
    if (auth.name != "Administrator") {
      // ใช้ Future.microtask เพื่อเลี่ยง setState ระหว่าง build
      Future.microtask(() {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      });

      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // ถ้าเป็น admin จริง แสดงหน้า office ได้
    return Scaffold(
      appBar: AppBar(
        title: const Text('Office (Back Office)'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('ยินดีต้อนรับ Administrator'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // ตัวอย่างปุ่มไปหน้า settings ในอนาคต
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OfficeSettingsScreen(),
                  ),
                );
              },
              child: const Text('ตั้งค่าระบบ (ตัวอย่าง)'),
            ),
          ],
        ),
      ),
    );
  }
}

class OfficeSettingsScreen extends StatelessWidget {
  const OfficeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    // กันกรณี user ปกติหลุดมาหน้านี้โดยตรง
    if (auth.name != "Administrator") {
      Future.microtask(() {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      });

      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Office Settings'),
      ),
      body: const Center(
        child: Text('หน้านี้สำหรับตั้งค่าระบบ (เฉพาะ Admin)'),
      ),
    );
  }
}