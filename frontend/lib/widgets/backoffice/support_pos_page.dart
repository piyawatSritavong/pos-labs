import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:frontend/config/api_config.dart';
import 'package:frontend/providers/auth_provider.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

String _buildWatcherWsUrl(String token) {
  return ApiConfig.wsUrl('/ws/pos-mirror', {'token': token});
}

class SupportPosPage extends StatefulWidget {
  const SupportPosPage({super.key});

  @override
  State<SupportPosPage> createState() => _SupportPosPageState();
}

class _SupportPosPageState extends State<SupportPosPage> {
  // ── Auth gate ──
  bool _authenticated = false;
  bool _isVerifying = false;
  String? _authError;
  final _passwordController = TextEditingController();

  WebSocketChannel? _channel;
  List<Map<String, dynamic>> _onlineBroadcasters = [];
  String? _watchingId;
  String? _watchingName;
  Map<String, dynamic>? _posState;
  DateTime? _lastUpdated;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Do NOT auto-connect — wait for password verification.
  }

  Future<void> _verifyPassword() async {
    final auth = context.read<AuthProvider>();
    final username = auth.username;
    final password = _passwordController.text.trim();
    if (username == null || username.isEmpty || password.isEmpty) return;

    setState(() {
      _isVerifying = true;
      _authError = null;
    });

    try {
      final ok = await ApiService.verifyPassword(
        username: username,
        password: password,
      );
      if (!mounted) return;
      if (ok) {
        setState(() {
          _authenticated = true;
          _isVerifying = false;
        });
        _connect();
      } else {
        setState(() {
          _authError = 'รหัสผ่านไม่ถูกต้อง';
          _isVerifying = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _authError = 'รหัสผ่านไม่ถูกต้อง';
        _isVerifying = false;
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _channel?.sink.close();
    super.dispose();
  }

  Widget _buildAuthGate() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 40,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'กรุณายืนยันตัวตน',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ป้อนรหัสผ่านของบัญชีนี้เพื่อเข้าดู Support POS',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'รหัสผ่าน',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    errorText: _authError,
                  ),
                  onSubmitted: (_) => _verifyPassword(),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isVerifying ? null : _verifyPassword,
                  child: _isVerifying
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('ยืนยัน'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _connect() {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    final uri = Uri.parse(_buildWatcherWsUrl(token));
    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      _onMessage,
      onError: (e) {
        if (mounted) setState(() => _error = e.toString());
      },
      onDone: () {
        if (mounted) {
          setState(() => _error = 'ขาดการเชื่อมต่อ กรุณารีเฟรช');
        }
      },
    );
  }

  void _onMessage(dynamic raw) {
    if (!mounted) return;
    final data = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (data['type']) {
      case 'online_list':
        final list =
            (data['broadcasters'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            [];
        setState(() => _onlineBroadcasters = list);
      case 'pos_state':
        setState(() {
          _posState = data;
          _lastUpdated = DateTime.now();
        });
    }
  }

  void _watchStaff(String userId, String userName) {
    _channel?.sink.add(jsonEncode({'type': 'watch', 'targetUserId': userId}));
    setState(() {
      _watchingId = userId;
      _watchingName = userName;
      _posState = null;
      _lastUpdated = null;
    });
  }

  void _refresh() {
    _channel?.sink.close();
    setState(() {
      _onlineBroadcasters = [];
      _watchingId = null;
      _watchingName = null;
      _posState = null;
      _lastUpdated = null;
      _error = null;
    });
    _connect();
  }

  @override
  Widget build(BuildContext context) {
    if (!_authenticated) {
      return _buildAuthGate();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopBar(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOnlinePanel(),
              const VerticalDivider(width: 1),
              Expanded(child: _buildMirrorPanel()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Text(
            'Support POS — Monitor',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'รีเฟรช',
            onPressed: _refresh,
          ),
        ],
      ),
    );
  }

  Widget _buildOnlinePanel() {
    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: AppColors.surface,
            child: Row(
              children: [
                const Icon(Icons.circle, color: Colors.green, size: 10),
                const SizedBox(width: 6),
                Text(
                  'Online (${_onlineBroadcasters.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_onlineBroadcasters.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'ไม่มีพนักงานออนไลน์',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _onlineBroadcasters.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, i) {
                  final staff = _onlineBroadcasters[i];
                  final id = staff['id'] as String? ?? '';
                  final name = staff['name'] as String? ?? id;
                  final isSelected = _watchingId == id;
                  return InkWell(
                    onTap: () => _watchStaff(id, name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.08)
                          : null,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.circle,
                            color: Colors.green,
                            size: 8,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: AppColors.primary,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMirrorPanel() {
    if (_watchingId == null) {
      return const Center(
        child: Text(
          'เลือกพนักงานเพื่อดูหน้าจอ POS',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return _POSMirrorView(
      staffName: _watchingName ?? _watchingId!,
      state: _posState,
      lastUpdated: _lastUpdated,
    );
  }
}

// ---------------------------------------------------------------------------
// POSMirrorView — read-only replica of home_screen.dart layout
// ---------------------------------------------------------------------------
class _POSMirrorView extends StatelessWidget {
  const _POSMirrorView({
    required this.staffName,
    required this.state,
    required this.lastUpdated,
  });

  final String staffName;
  final Map<String, dynamic>? state;
  final DateTime? lastUpdated;

  static const _dialogLabels = {
    'return': 'กำลังรับคืนสินค้า',
    'hold_bill': 'กำลังพักบิล',
    'stock': 'กำลังดูสต็อก',
    'bill_log': 'กำลังดูประวัติบิล',
    'member_register': 'กำลังลงทะเบียนสมาชิก',
    'physical_count': 'กำลังนับสต็อก',
    'daily_close': 'กำลังปิดยอดประจำวัน',
    'transfer_receive': 'กำลังรับโอนสินค้า',
  };

  static const _dialogIcons = {
    'return': Icons.assignment_return_outlined,
    'hold_bill': Icons.pause_circle_outline,
    'stock': Icons.warning_amber_rounded,
    'bill_log': Icons.history_rounded,
    'member_register': Icons.person_add_outlined,
    'physical_count': Icons.inventory_2_outlined,
    'daily_close': Icons.calculate_outlined,
    'transfer_receive': Icons.local_shipping_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLiveBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildLiveBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            staffName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const Spacer(),
          if (lastUpdated != null)
            Text(
              'อัปเดต ${_timeAgo(lastUpdated!)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (state == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'รอข้อมูลจากพนักงาน...',
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      );
    }

    final activeDialog = state!['activeDialog'] as String?;
    final lastBarcode = state!['lastBarcode'] as String?;
    final lastAction = state!['lastAction'] as String?;
    final items =
        (state!['items'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final subtotal = _toDouble(state!['subtotal']);
    final discount = _toDouble(state!['discount']);
    final tax = _toDouble(state!['tax']);
    final taxRate = _toDouble(state!['taxRate']).round();
    final total = _toDouble(state!['total']);
    final member = state!['member'] as Map<String, dynamic>?;
    final billId = state!['billId'] as String?;
    final isAwaitingCash = state!['isAwaitingCash'] == true;
    final isAwaitingQr = state!['isAwaitingQr'] == true;
    final showThankYou = state!['showThankYou'] == true;
    final dialogState = state!['dialogState'] as Map<String, dynamic>?;

    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeaderBar(activeDialog, lastBarcode),
          const SizedBox(height: 24),
          Expanded(
            child: Stack(
              children: [
                // ── Base layout — cart full width ──────────────────────────────
                Positioned.fill(
                  child: _buildCartPanel(
                    items: items,
                    subtotal: subtotal,
                    discount: discount,
                    tax: tax,
                    taxRate: taxRate,
                    total: total,
                    member: member,
                    billId: billId,
                    lastAction: lastAction,
                  ),
                ),

                // ── Payment overlay ─────────────────────────────────────────
                if (isAwaitingCash || isAwaitingQr)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.35),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isAwaitingQr
                                  ? Icons.qr_code_2
                                  : Icons.payments_outlined,
                              size: 48,
                              color: AppColors.primary,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isAwaitingQr
                                  ? 'รอสแกน QR'
                                  : 'รอรับเงินสด\n฿${_fmt(_toDouble(state!['cashAmount']))}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ── Thank you overlay ───────────────────────────────────────
                if (showThankYou)
                  Positioned.fill(
                    child: Container(
                      color: Colors.green.withValues(alpha: 0.85),
                      alignment: Alignment.center,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: Colors.white,
                            size: 64,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'ชำระเงินสำเร็จ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Dialog overlay (full content) ───────────────────────────
                if (dialogState != null)
                  Positioned.fill(
                    child: _buildDialogOverlay(activeDialog, dialogState),
                  )
                // ── Active dialog chip (fallback, no detailed state) ────────
                else if (activeDialog != null)
                  Positioned(
                    bottom: 100,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(AppSizes.radius),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _dialogIcons[activeDialog] ?? Icons.touch_app,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _dialogLabels[activeDialog] ??
                                  'กำลังใช้งาน: $activeDialog',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildBarcodeBar(lastBarcode),
        ],
      ),
    );
  }

  // ── Cart panel — CartSummarySection replica ─────────────────────────────
  Widget _buildCartPanel({
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double discount,
    required double tax,
    required int taxRate,
    required double total,
    required Map<String, dynamic>? member,
    required String? billId,
    required String? lastAction,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header + member row
          Row(
            children: [
              const Text(
                'ตะกร้าสินค้า',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  alignment: Alignment.centerLeft,
                  child: member != null
                      ? Row(
                          children: [
                            const Icon(
                              Icons.person,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${member['code'] ?? ''} ${member['name'] ?? ''}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          'เบอร์โทรสมาชิก',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: null, child: const Text('ผูกสมาชิก')),
            ],
          ),
          if (billId != null && billId.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'บิล #$billId',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useSplit = constraints.maxWidth >= 760;
                final itemList = _buildItemList(items, lastAction);
                final pricing = _buildPricingPanel(
                  subtotal: subtotal,
                  discount: discount,
                  tax: tax,
                  taxRate: taxRate,
                  total: total,
                  lastAction: lastAction,
                );
                if (useSplit) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: itemList),
                      const SizedBox(width: 16),
                      Expanded(flex: 4, child: pricing),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: itemList),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: pricing,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemList(List<Map<String, dynamic>> items, String? lastAction) {
    final isQtyAction = lastAction == 'qty_add' || lastAction == 'qty_remove';
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                flex: 6,
                child: Text(
                  'ชื่อ',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const Expanded(
                flex: 3,
                child: Text(
                  'จำนวน',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const Expanded(
                flex: 3,
                child: Text(
                  'ราคา',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              if (isQtyAction) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    lastAction == 'qty_add' ? '+จำนวน' : '-จำนวน',
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: AppColors.border.withValues(alpha: 0.7)),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'ยังไม่มีสินค้าในตะกร้า',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  )
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final item = items[i];
                      final name = item['partName']?.toString() ?? '';
                      final code = item['partCode']?.toString() ?? '';
                      final qty = item['qty'] ?? 0;
                      final lineTotal = _toDouble(item['lineTotal']);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 6,
                              child: Text(
                                '$name • $code',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                '$qty',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                '฿${_fmt(lineTotal)}',
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingPanel({
    required double subtotal,
    required double discount,
    required double tax,
    required int taxRate,
    required double total,
    required String? lastAction,
  }) {
    const gap = SizedBox(height: 10);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _totalRow('ราคารวม', '฿${_fmt(subtotal)}'),
          const SizedBox(height: 4),
          _totalRow(
            'ส่วนลด',
            '- ฿${_fmt(discount)}',
            color: discount > 0 ? AppColors.danger : null,
          ),
          const SizedBox(height: 4),
          _totalRow('ภาษี ($taxRate%)', '฿${_fmt(tax)}'),
          gap,
          Row(
            children: [
              const Text(
                'ส่วนลด',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              for (final entry in [
                ('5%', 'discount_5'),
                ('10%', 'discount_10'),
                ('15%', 'discount_15'),
                ('20%', 'discount_20'),
              ]) ...[
                Builder(
                  builder: (context) {
                    final isActive = lastAction == entry.$2;
                    return OutlinedButton(
                      onPressed: null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 11),
                        foregroundColor: isActive ? Colors.red : null,
                        side: isActive
                            ? const BorderSide(color: Colors.red, width: 2)
                            : null,
                      ),
                      child: Text(entry.$1),
                    );
                  },
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
          gap,
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    discount > 0 ? _fmt(discount) : 'ส่วนลด',
                    style: TextStyle(
                      color: discount > 0 ? AppColors.text : AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                alignment: Alignment.center,
                child: const Text('%', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
          gap,
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Text(
                  'รวมสุทธิ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  '฿${_fmt(total)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          gap,
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor: lastAction == 'pay'
                    ? AppColors.primary.withValues(alpha: 0.85)
                    : AppColors.primary.withValues(alpha: 0.4),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
                side: lastAction == 'pay'
                    ? const BorderSide(color: Colors.red, width: 2)
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'ชำระเงิน',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          gap,
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: null,
                  style: lastAction == 'hold'
                      ? OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red, width: 2),
                        )
                      : null,
                  child: const Text('พักบิล'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: null,
                  style: lastAction == 'clear'
                      ? OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red, width: 2),
                        )
                      : OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                  child: const Text('ล้างบิล'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Header bar ───────────────────────────────────────────────────────────
  Widget _buildHeaderBar(String? activeDialog, String? lastBarcode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          _buildSearchBar(lastBarcode),
          const SizedBox(width: 24),
          _buildActionIcons(activeDialog),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                staffName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Text(
                'POS Mirror',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Text(
              staffName.isNotEmpty ? staffName[0].toUpperCase() : '?',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(String? lastBarcode) {
    final hasValue = lastBarcode != null && lastBarcode.isNotEmpty;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(AppSizes.radius),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: AppColors.muted, size: 18),
            const SizedBox(width: 8),
            Text(
              hasValue ? lastBarcode : 'เลือกสินค้า',
              style: TextStyle(
                color: hasValue ? AppColors.text : AppColors.muted,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionIcons(String? activeDialog) {
    const actions = [
      ('return', Icons.assignment_return_outlined),
      ('hold_bill', Icons.pause_circle_outline),
      ('stock', Icons.warning_amber_rounded),
      ('bill_log', Icons.history_rounded),
      ('member_register', Icons.person_add_outlined),
      ('physical_count', Icons.inventory_2_outlined),
      ('daily_close', Icons.calculate_outlined),
      ('transfer_receive', Icons.local_shipping_outlined),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: actions.map((entry) {
        final isActive = activeDialog == entry.$1;
        return Container(
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: isActive ? Colors.red.withValues(alpha: 0.12) : AppColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive ? Colors.red : AppColors.border,
              width: isActive ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Icon(
            entry.$2,
            size: 20,
            color: isActive ? Colors.red : AppColors.muted,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBarcodeBar(String? lastBarcode) {
    final hasValue = lastBarcode != null && lastBarcode.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                hasValue ? lastBarcode : 'สแกนบาร์โค้ด...',
                style: TextStyle(
                  color: hasValue ? AppColors.text : AppColors.muted,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                disabledBackgroundColor: AppColors.accent.withValues(
                  alpha: 0.6,
                ),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('SCAN'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dialog overlay ───────────────────────────────────────────────────────
  Widget _buildDialogOverlay(
    String? dialogKey,
    Map<String, dynamic> dialogState,
  ) {
    final type = dialogKey ?? dialogState['type'] as String? ?? '';
    final icon = _dialogIcons[type] ?? Icons.touch_app;
    final label = _dialogLabels[type] ?? 'กำลังใช้งาน: $type';

    return Container(
      color: Colors.black.withValues(alpha: 0.50),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
          child: Container(
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: AppShadows.soft,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 20),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _buildDialogContent(dialogState),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDialogContent(Map<String, dynamic> dialogState) {
    switch (dialogState['type'] as String? ?? '') {
      case 'member_register':
        return _buildMemberRegisterContent(dialogState);
      case 'stock':
        return _buildStockContent(dialogState);
      case 'bill_log':
        return _buildBillLogContent(dialogState);
      case 'hold_bill':
        return _buildHoldBillContent(dialogState);
      case 'return':
        return _buildReturnContent(dialogState);
      case 'physical_count':
        return _buildPhysicalCountContent(dialogState);
      case 'daily_close':
        return _buildDailyCloseContent(dialogState);
      case 'transfer_receive':
        return _buildTransferReceiveContent(dialogState);
      default:
        return Center(
          child: Text(
            'ไม่ทราบประเภท: ${dialogState['type']}',
            style: const TextStyle(color: AppColors.muted),
          ),
        );
    }
  }

  Widget _buildMemberRegisterContent(Map<String, dynamic> s) {
    final stage = s['stage'] as String? ?? 'filling';
    if (stage == 'success') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
          const SizedBox(height: 8),
          Text(
            'ลงทะเบียนสำเร็จ: ${s['name'] ?? ''}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _readonlyField('ชื่อ', s['name']?.toString() ?? ''),
        const SizedBox(height: 8),
        _readonlyField('เบอร์โทร', s['phone']?.toString() ?? ''),
        const SizedBox(height: 8),
        _readonlyField('อีเมล', s['email']?.toString() ?? ''),
        if (stage == 'error') ...[
          const SizedBox(height: 8),
          const Text(
            'เกิดข้อผิดพลาด',
            style: TextStyle(color: AppColors.danger),
          ),
        ],
      ],
    );
  }

  Widget _readonlyField(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              value.isEmpty ? '-' : value,
              style: TextStyle(
                color: value.isEmpty ? AppColors.muted : AppColors.text,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStockContent(Map<String, dynamic> s) {
    final items =
        (s['items'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'สต็อกเพียงพอทุกสินค้า',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final item = items[i];
        final totalQty = _toDouble(item['totalQty']);
        final addresses =
            (item['addresses'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            [];
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${item['partName'] ?? item['partCode'] ?? '-'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${totalQty.toStringAsFixed(0)} ชิ้น',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              if (addresses.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  addresses
                      .map(
                        (a) =>
                            '${a['label'] ?? '-'}: ${_toDouble(a['qty']).toStringAsFixed(0)}',
                      )
                      .join(', '),
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildBillLogContent(Map<String, dynamic> s) {
    final bills =
        (s['bills'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
    if (bills.isEmpty) {
      return const Center(
        child: Text(
          'วันนี้ยังไม่มีบิล',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return ListView.separated(
      itemCount: bills.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final bill = bills[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${bill['id'] ?? '-'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${bill['itemCount'] ?? 0} รายการ',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(width: 12),
              Text(
                '฿${_fmt(_toDouble(bill['total']))}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHoldBillContent(Map<String, dynamic> s) {
    final bills =
        (s['bills'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
    final action = s['action'] as String?;
    final targetId = s['targetBillId'] as String?;
    if (bills.isEmpty) {
      return const Center(
        child: Text(
          'ไม่มีบิลที่ถูกพักไว้',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return ListView.separated(
      itemCount: bills.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final bill = bills[i];
        final id = bill['id']?.toString() ?? '';
        final isTarget = targetId == id;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isTarget
                ? (action == 'deleting'
                      ? AppColors.danger.withValues(alpha: 0.08)
                      : AppColors.primary.withValues(alpha: 0.08))
                : AppColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isTarget
                  ? (action == 'deleting'
                        ? AppColors.danger
                        : AppColors.primary)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'บิล $id',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${bill['itemCount'] ?? 0} รายการ • ฿${_fmt(_toDouble(bill['total']))}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              if (isTarget && action != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: action == 'deleting'
                        ? AppColors.danger
                        : AppColors.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    action == 'deleting' ? 'กำลังลบ' : 'กำลังดึงกลับ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildReturnContent(Map<String, dynamic> s) {
    final invoiceId = s['invoiceId'] as String? ?? '';
    final bill = s['bill'] as Map<String, dynamic>?;
    final items =
        (s['items'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bill != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'บิลอ้างอิง: ${bill['id'] ?? invoiceId}  •  ฿${_fmt(_toDouble(bill['total']))}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          )
        else
          Text(
            'ค้นหาบิล: $invoiceId',
            style: const TextStyle(color: AppColors.muted),
          ),
        const SizedBox(height: 8),
        Flexible(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (_, i) {
              final item = items[i];
              final selected = (item['selectedQty'] as num?)?.toInt() ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected > 0
                      ? AppColors.danger.withValues(alpha: 0.06)
                      : AppColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected > 0
                        ? AppColors.danger.withValues(alpha: 0.4)
                        : AppColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item['partName'] ?? item['partCode'] ?? '-'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '${item['maxReturnable'] ?? 0} max',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: selected > 0 ? AppColors.danger : AppColors.bg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected > 0
                              ? AppColors.danger
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        '$selected',
                        style: TextStyle(
                          color: selected > 0 ? Colors.white : AppColors.muted,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPhysicalCountContent(Map<String, dynamic> s) {
    final stage = s['stage'] as String? ?? 'counting';
    final items =
        (s['items'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? [];
    final varianceReport = s['varianceReport'] as Map<String, dynamic>?;

    if (stage == 'variance' && varianceReport != null) {
      final varItems =
          (varianceReport['items'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          items;
      final withVariance = varItems
          .where((i) => _toDouble(i['variance']) != 0)
          .length;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.check_circle_outline,
                color: Colors.green,
                size: 20,
              ),
              const SizedBox(width: 6),
              const Text(
                'ส่งยืนยันสำเร็จ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              const Spacer(),
              Text(
                'มีความต่าง $withVariance รายการ',
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.separated(
              itemCount: varItems.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (_, i) {
                final item = varItems[i];
                final variance = _toDouble(item['variance']);
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: variance < 0
                        ? AppColors.danger.withValues(alpha: 0.06)
                        : variance > 0
                        ? Colors.green.withValues(alpha: 0.06)
                        : AppColors.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${item['partName'] ?? item['partCode'] ?? '-'}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        '${_toDouble(item['systemQty']).toStringAsFixed(0)} → ${_toDouble(item['countedQty']).toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        (variance >= 0 ? '+' : '') +
                            variance.toStringAsFixed(0),
                        style: TextStyle(
                          color: variance < 0
                              ? AppColors.danger
                              : variance > 0
                              ? Colors.green
                              : AppColors.muted,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final item = items[i];
        final system = _toDouble(item['systemQty']);
        final counted = _toDouble(item['countedQty']);
        final diff = counted - system;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${item['partName'] ?? item['partCode'] ?? '-'}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text(
                'ระบบ: ${system.toStringAsFixed(0)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: diff < 0
                      ? AppColors.danger.withValues(alpha: 0.1)
                      : AppColors.bg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: diff != 0
                        ? (diff < 0 ? AppColors.danger : Colors.green)
                        : AppColors.border,
                  ),
                ),
                child: Text(
                  counted.toStringAsFixed(0),
                  style: TextStyle(
                    color: diff < 0 ? AppColors.danger : AppColors.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDailyCloseContent(Map<String, dynamic> s) {
    final summary = s['summary'] as Map<String, dynamic>? ?? {};
    final alreadyClosed = s['alreadyClosed'] == true;
    final closed = s['stage'] == 'closed';
    final notes = s['notes'] as String? ?? '';
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (alreadyClosed || closed)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: closed
                    ? Colors.green.withValues(alpha: 0.1)
                    : AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: closed ? Colors.green : AppColors.accent,
                ),
              ),
              child: Text(
                closed ? 'ปิดยอดสำเร็จ' : 'ปิดยอดแล้ววันนี้',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: closed ? Colors.green : AppColors.accent,
                ),
              ),
            ),
          _dialogSummaryRow(
            'ยอดขายรวม',
            '฿${_fmt(_toDouble(summary['totalSales']))}',
            bold: true,
          ),
          _dialogSummaryRow(
            'เงินสด',
            '฿${_fmt(_toDouble(summary['totalCash']))}',
          ),
          _dialogSummaryRow(
            'โอนเงิน/QR',
            '฿${_fmt(_toDouble(summary['totalTransfer']))}',
          ),
          _dialogSummaryRow('จำนวนบิล', '${summary['totalBills'] ?? 0} ใบ'),
          _dialogSummaryRow(
            'ยอดคืนสินค้า',
            '฿${_fmt(_toDouble(summary['totalReturns']))}',
            color: AppColors.danger,
          ),
          _dialogSummaryRow(
            'ยอดสุทธิ',
            '฿${_fmt(_toDouble(summary['netAmount']))}',
            bold: true,
            color: AppColors.primary,
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'หมายเหตุ: $notes',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dialogSummaryRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: bold ? AppColors.text : AppColors.muted,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color ?? AppColors.text,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferReceiveContent(Map<String, dynamic> s) {
    final transfers =
        (s['transfers'] as List?)?.whereType<Map<String, dynamic>>().toList() ??
        [];
    final expandedId = s['expandedId'] as String?;
    if (transfers.isEmpty) {
      return const Center(
        child: Text(
          'ไม่มีสินค้ารอรับ',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return ListView.separated(
      itemCount: transfers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final transfer = transfers[i];
        final id = transfer['id']?.toString() ?? '';
        final fromBranch = transfer['fromBranch'] as String? ?? '-';
        final isExpanded = expandedId == id;
        final items =
            (transfer['items'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            [];
        return Container(
          decoration: BoxDecoration(
            color: isExpanded
                ? AppColors.primary.withValues(alpha: 0.04)
                : AppColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isExpanded
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Transfer #$id • จาก $fromBranch',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppColors.muted,
                      size: 16,
                    ),
                  ],
                ),
              ),
              if (isExpanded && items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: items.map((item) {
                      final dispatched = _toDouble(item['dispatchedQty']);
                      final received = _toDouble(item['receivedQty']);
                      final diff = received - dispatched;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item['partName'] ?? item['partCode'] ?? '-'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Text(
                              '${dispatched.toStringAsFixed(0)} → ${received.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                              ),
                            ),
                            if (diff != 0) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: diff < 0
                                      ? AppColors.danger
                                      : Colors.green,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  (diff >= 0 ? '+' : '') +
                                      diff.toStringAsFixed(0),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Shared helpers ───────────────────────────────────────────────────────
  Widget _totalRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
    double fontSize = 13,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(color: AppColors.muted, fontSize: fontSize),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color,
            fontSize: fontSize,
          ),
        ),
      ],
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static String _fmt(double v) => v.toStringAsFixed(2);

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 5) return 'เมื่อกี้';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ที่แล้ว';
    return '${diff.inMinutes}m ที่แล้ว';
  }
}
