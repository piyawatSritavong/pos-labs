import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/app_dialog_service.dart';

class SessionGuard extends StatefulWidget {
  const SessionGuard({required this.child, super.key});

  final Widget child;

  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard> {
  Timer? _timer;
  bool _polling = false;
  bool _conflictDialogOpen = false;
  bool _resolvingConflict = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _poll();
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling || !mounted) return;
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || token.isEmpty || auth.isCustomerDisplay) return;
    _polling = true;
    try {
      final result = await ApiService.getSessionState(token);
      if (!mounted || auth.token != token) return;
      final state = result['state']?.toString() ?? 'active';
      if (state == 'active') {
        if (auth.isSessionPending) {
          await auth.refreshCurrentUser();
        } else {
          await auth.updateSessionState('active');
        }
        if (result['pendingLogin'] is Map<String, dynamic>) {
          unawaited(
            _showConflict(result['pendingLogin'] as Map<String, dynamic>),
          );
        } else if (_conflictDialogOpen) {
          appNavigatorKey.currentState?.pop();
          _conflictDialogOpen = false;
        }
      } else if (state == 'pending') {
        await auth.updateSessionState('pending');
      } else if (state == 'rejected') {
        await AppDialogService.showError(
          context,
          title: 'ไม่อนุญาตให้เข้าสู่ระบบ',
          error: Exception('rejected'),
          fallback: 'อุปกรณ์เดิมเลือกใช้งานบัญชีนี้ต่อ',
        );
        await auth.logout(callBackend: false);
      } else if (state == 'replaced') {
        await AppDialogService.showSessionExpired(context, auth.expireSession);
      }
    } catch (_) {
      // 401 is handled once by ApiHttpEvents. Transient heartbeat failures do
      // not interrupt an otherwise usable permanent session.
    } finally {
      _polling = false;
    }
  }

  Future<void> _showConflict(Map<String, dynamic> pending) async {
    if (_conflictDialogOpen || _resolvingConflict || !mounted) return;
    _conflictDialogOpen = true;
    final ip = pending['ip']?.toString().trim() ?? '';
    final decision = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('มีผู้เข้าสู่ระบบซ้อน'),
          content: Text(
            ip.isEmpty
                ? 'มีผู้เข้าสู่ระบบด้วยบัญชีนี้จากอุปกรณ์อื่น'
                : 'มีผู้เข้าสู่ระบบด้วยบัญชีนี้จากอุปกรณ์อื่น\nIP: $ip',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('leave'),
              child: const Text('ออกจากระบบ'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop('stay'),
              child: const Text('อยู่ต่อ'),
            ),
          ],
        ),
      ),
    );
    _conflictDialogOpen = false;
    if (decision == null) return;
    _resolvingConflict = true;
    try {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final token = auth.token;
      if (token == null) return;
      await ApiService.resolveSessionConflict(token: token, decision: decision);
      if (decision == 'leave') {
        await auth.logout(callBackend: false);
      }
    } catch (error) {
      if (mounted) {
        await AppDialogService.showError(
          context,
          error: error,
          fallback: 'ยืนยันการเข้าสู่ระบบไม่สำเร็จ',
        );
      }
    } finally {
      _resolvingConflict = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isSessionPending) return widget.child;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: const _PendingSessionCard(),
        ),
      ),
    );
  }
}

class _PendingSessionCard extends StatelessWidget {
  const _PendingSessionCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text(
              'กำลังรอการยืนยันจากอุปกรณ์เดิม',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'หากอุปกรณ์เดิมไม่ได้ใช้งาน ระบบจะอนุญาตให้อุปกรณ์นี้เข้าแทนอัตโนมัติภายใน 60 วินาที',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => context.read<AuthProvider>().logout(),
              child: const Text('ยกเลิกการเข้าสู่ระบบ'),
            ),
          ],
        ),
      ),
    );
  }
}
