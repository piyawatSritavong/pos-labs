import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:frontend/services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// "เพิ่มสินค้าด้วยไฟล์" — pick a filled-in template and upload it.
///
/// The import is all-or-nothing on the server, so this dialog only ever
/// reports one of two outcomes: every row was created, or nothing was and here
/// is the list of cells to fix.
///
/// Returns the outcome when the file was applied, or null when the user closed
/// the dialog without importing.
Future<PartsImportResult?> showPartsImportDialog(
  BuildContext context,
  String token,
) {
  return showDialog<PartsImportResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PartsImportDialog(token: token),
  );
}

class _PartsImportDialog extends StatefulWidget {
  const _PartsImportDialog({required this.token});

  final String token;

  @override
  State<_PartsImportDialog> createState() => _PartsImportDialogState();
}

class _PartsImportDialogState extends State<_PartsImportDialog> {
  PartsImportLimits _limits = PartsImportLimits.fallback;
  String? _filename;
  Uint8List? _bytes;
  bool _isUploading = false;
  String? _error;
  PartsImportResult? _result;

  @override
  void initState() {
    super.initState();
    // Show the server's own caps rather than a second copy that can drift.
    ApiService.getPartsImportLimits(widget.token)
        .then((limits) {
          if (mounted) {
            setState(() => _limits = limits);
          }
        })
        .catchError((_) {
          /* keep the fallback */
        });
  }

  String get _sizeLabel {
    final bytes = _bytes;
    if (bytes == null) {
      return '';
    }
    if (bytes.length < 1024) {
      return '${bytes.length} B';
    }
    if (bytes.length < 1024 * 1024) {
      return '${(bytes.length / 1024).round()} KB';
    }
    return '${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _downloadTemplate() async {
    final url = ApiService.partsImportTemplateUrl();
    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      setState(() => _error = 'เปิดลิงก์ดาวน์โหลดไม่สำเร็จ: $url');
    }
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _limits.extensions,
      withData: true, // web has no file path — always read the bytes
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'อ่านไฟล์ไม่สำเร็จ กรุณาเลือกใหม่');
      return;
    }
    // Check here as well as on the server so an oversized file is rejected
    // before it goes over the wire.
    if (!file.name.toLowerCase().endsWith('.xlsx')) {
      setState(() {
        _error = 'รองรับเฉพาะไฟล์ Excel นามสกุล .xlsx เท่านั้น';
        _bytes = null;
        _filename = null;
      });
      return;
    }
    if (bytes.length > _limits.maxFileBytes) {
      setState(() {
        _error =
            'ไฟล์ใหญ่เกิน ${_limits.maxFileLabel} (รองรับประมาณ ${_limits.maxRows} รายการต่อครั้ง)';
        _bytes = null;
        _filename = null;
      });
      return;
    }
    setState(() {
      _filename = file.name;
      _bytes = bytes;
      _error = null;
      _result = null;
    });
  }

  Future<void> _upload() async {
    final bytes = _bytes;
    final filename = _filename;
    if (bytes == null || filename == null) return;

    setState(() {
      _isUploading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ApiService.importPartsFromExcel(
        token: widget.token,
        filename: filename,
        bytes: bytes,
      );
      if (!mounted) return;
      if (result.ok) {
        Navigator.of(context).pop(result);
        return;
      }
      setState(() {
        _result = result;
        _isUploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;

    return AlertDialog(
      title: const Text('เพิ่มสินค้าด้วยไฟล์ Excel'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _RulesBox(limits: _limits),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _isUploading ? null : _downloadTemplate,
                    icon: const Icon(Icons.download),
                    label: const Text('ดาวน์โหลดเทมเพลต'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _isUploading ? null : _pickFile,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      _filename == null ? 'เลือกไฟล์' : 'เปลี่ยนไฟล์',
                    ),
                  ),
                ],
              ),
              if (_filename != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_filename  ($_sizeLabel)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                _Banner(
                  color: theme.colorScheme.errorContainer,
                  textColor: theme.colorScheme.onErrorContainer,
                  icon: Icons.error_outline,
                  text: _error!,
                ),
              ],
              if (result != null && !result.ok) ...[
                const SizedBox(height: 12),
                _Banner(
                  color: theme.colorScheme.errorContainer,
                  textColor: theme.colorScheme.onErrorContainer,
                  icon: Icons.report_problem_outlined,
                  text: result.message,
                ),
                if (result.rows.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Scrollbar(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: result.rows.length,
                        itemBuilder: (_, index) {
                          final row = result.rows[index];
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: const Icon(Icons.close, size: 16),
                            title: Text(row.label),
                            subtitle: Text(row.message),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isUploading ? null : () => Navigator.of(context).pop(),
          child: const Text('ปิด'),
        ),
        ElevatedButton(
          onPressed: (_bytes == null || _isUploading) ? null : _upload,
          child: _isUploading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('อัปโหลด'),
        ),
      ],
    );
  }
}

class _RulesBox extends StatelessWidget {
  const _RulesBox({required this.limits});

  final PartsImportLimits limits;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rules = [
      'รองรับเฉพาะไฟล์ Excel นามสกุล .xlsx ขนาดไม่เกิน ${limits.maxFileLabel}',
      'เพิ่มได้ครั้งละไม่เกิน ${limits.maxRows} รายการ',
      'กรอกในชีตแรก แถวที่ 1 เป็นหัวคอลัมน์ ห้ามแก้ไข',
      'ต้องกรอก: ชื่อสินค้า, ราคาขาย — ที่เหลือเว้นว่างได้',
      'ถ้ารหัสสินค้าหรือชื่อสินค้าตรงกับของที่มีอยู่ = อัปเดตของเดิม '
          '(บวกจำนวนเข้าคลัง แก้ต้นทุน/ราคา) ชื่อและบาร์โค้ดจะไม่ถูกแก้',
      'ถ้าไม่ตรงกับอะไรเลย = สินค้าใหม่ เว้นรหัสว่างไว้ระบบจะออกรหัสให้',
      'แถวที่ชี้ไปสินค้าตัวเดียวกัน จำนวนจะถูกรวมเข้าด้วยกัน',
      'สินค้าเข้าคลังหลักเท่านั้น',
      'ถ้ามีข้อผิดพลาดแม้แต่บรรทัดเดียว จะไม่บันทึกทั้งไฟล์',
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final rule in rules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(rule, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.textColor,
    required this.icon,
    required this.text,
  });

  final Color color;
  final Color textColor;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: textColor)),
          ),
        ],
      ),
    );
  }
}
