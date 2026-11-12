import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/api_error.dart';
import '../../core/session.dart';
import '../../ui/neo.dart';
import '../../ui/neo_parts.dart';
import '../../ui/theme.dart';

const _avatars = [
  (Color(0xFFEEF2FF), Color(0xFF4F46E5)),
  (Color(0xFFECFDF5), Color(0xFF059669)),
  (Color(0xFFF5F3FF), Color(0xFF6D28D9)),
  (Color(0xFFFFFBEB), Color(0xFFB45309)),
  (Color(0xFFFFF1F2), Color(0xFFE11D48)),
];
const _poses = ['1 · Nhìn thẳng', '2 · Quay trái', '3 · Quay phải', '4', '5'];

String _ago(String iso) {
  final d = DateTime.now().difference(DateTime.parse(iso).toLocal());
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)} phút';
  if (d.inHours < 24) return '${d.inHours} giờ';
  return d.inDays == 1 ? 'hôm qua' : '${d.inDays} ngày';
}

/// Artboard "Web · Duyệt khuôn mặt" (Web_DuyetKhuonMat.dc.html). Rộng: hàng chờ + chi tiết; hẹp (điện thoại
/// giảng viên): danh sách, bấm để mở chi tiết. Dữ liệu: GET /faces/pending, /faces/{id}/photos, POST /review.
class FaceReviewPage extends StatefulWidget {
  const FaceReviewPage({super.key, required this.session, this.onCountChanged});
  final Session session;
  final ValueChanged<int>? onCountChanged;

  @override
  State<FaceReviewPage> createState() => _FaceReviewPageState();
}

class _FaceReviewPageState extends State<FaceReviewPage> {
  List<Map<String, dynamic>>? _items;
  int? _selected;
  String _filter = 'all';
  String? _error;

  ApiClient get _api => widget.session.api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await _api.get('/faces/pending') as List;
      if (!mounted) return;
      setState(() {
        _items = [for (final x in r) Map<String, dynamic>.from(x as Map)];
        if (!_items!.any((i) => i['id'] == _selected)) _selected = _items!.firstOrNull?['id'] as int?;
      });
      widget.onCountChanged?.call(_items!.length);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  List<Map<String, dynamic>> get _visible => [
        for (final i in _items ?? const <Map<String, dynamic>>[])
          if (_filter == 'all' || (_filter == 'update') == (i['is_update'] == true)) i,
      ];

  void _decided(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_items == null) return LoadingOrError(error: _error, onRetry: _load);
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 760;
      final items = _items!;
      final header = Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 16,
        runSpacing: 12,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('Duyệt khuôn mặt',
                style: TextStyle(fontSize: wide ? 28 : 22, fontWeight: FontWeight.w800, color: AppColors.text)),
            const SizedBox(height: 4),
            Text(items.isEmpty ? 'Không có yêu cầu nào đang chờ' : '${items.length} yêu cầu đang chờ',
                style: const TextStyle(fontSize: 15, color: AppColors.textMuted)),
          ]),
          _tabs(items),
        ],
      );
      final queue = NeoCard(
        padding: const EdgeInsets.all(8),
        radius: 18,
        child: Column(children: [
          if (_visible.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Hàng chờ trống.', style: TextStyle(color: AppColors.textMuted))),
          for (final (i, it) in _visible.indexed) _queueTile(it, i, wide),
        ]),
      );
      final sel = items.where((i) => i['id'] == _selected).firstOrNull;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(wide ? 32 : 16, wide ? 28 : 12, wide ? 32 : 16, wide ? 40 : 100),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: webContentMaxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              header,
              const SizedBox(height: 20),
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 340, child: queue),
                  const SizedBox(width: 20),
                  Expanded(
                    child: sel == null
                        ? const SizedBox.shrink()
                        : ReviewDetail(key: ValueKey(sel['id']), api: _api, item: sel, onDecided: _decided),
                  ),
                ])
              else
                queue,
            ]),
          ),
        ),
      );
    });
  }

  Widget _tabs(List<Map<String, dynamic>> items) {
    final first = items.where((i) => i['is_update'] != true).length;
    final tabs = {'all': 'Tất cả · ${items.length}', 'first': 'Lần đầu · $first', 'update': 'Cập nhật · ${items.length - first}'};
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.inputBorder, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final e in tabs.entries)
          Semantics(
            selected: _filter == e.key,
            button: true,
            child: GestureDetector(
              onTap: () => setState(() => _filter = e.key),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _filter == e.key ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: _filter == e.key ? const [BoxShadow(color: Color(0x140F172A), blurRadius: 2, offset: Offset(0, 1))] : null,
                ),
                child: Text(e.value,
                    style: TextStyle(fontSize: 14, fontWeight: _filter == e.key ? FontWeight.w600 : FontWeight.w400,
                        color: _filter == e.key ? AppColors.text : AppColors.textSecondary)),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _queueTile(Map<String, dynamic> it, int i, bool wide) {
    final (bg, fg) = _avatars[i % _avatars.length];
    final active = wide && it['id'] == _selected;
    final update = it['is_update'] == true;
    return Material(
      color: active ? AppColors.primarySoft : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (wide) {
            setState(() => _selected = it['id'] as int);
          } else {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(
                  appBar: AppBar(title: Text('${it['full_name']}'), backgroundColor: AppColors.background),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: ReviewDetail(api: _api, item: it, onDecided: (m) {
                      Navigator.of(context).pop();
                      _decided(m);
                    }),
                  ),
                )));
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            InitialsAvatar('${it['full_name']}', size: 42, round: true, bg: bg, fg: fg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${it['full_name']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
                Text('${it['student_code'] ?? it['username']} · ${_ago('${it['created_at']}')}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ]),
            ),
            Pill(update ? 'Cập nhật' : 'Lần đầu',
                bg: update ? AppColors.cardBorder : AppColors.primarySoft,
                fg: update ? AppColors.textSecondary : AppColors.primary, fontSize: 12,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3)),
          ]),
        ),
      ),
    );
  }
}

/// Chi tiết một yêu cầu: ảnh (mỗi lần mở là một lượt xem có ghi nhật ký), đối chiếu bằng mắt, duyệt / từ chối.
class ReviewDetail extends StatefulWidget {
  const ReviewDetail({super.key, required this.api, required this.item, required this.onDecided});
  final ApiClient api;
  final Map<String, dynamic> item;
  final ValueChanged<String> onDecided;

  @override
  State<ReviewDetail> createState() => _ReviewDetailState();
}

class _ReviewDetailState extends State<ReviewDetail> {
  List<Uint8List>? _photos;
  bool _matchesCard = false;
  bool _notReplay = false;
  final _reason = TextEditingController();
  String? _reasonError;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    try {
      final r = await widget.api.get('/faces/${widget.item['id']}/photos') as Map;
      final list = [for (final p in r['photos'] as List) base64Decode('$p'.split(',').last)];
      if (mounted) setState(() => _photos = list);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _decide(bool approve) async {
    final reason = _reason.text.trim();
    if (!approve && reason.isEmpty) {
      setState(() => _reasonError = 'Từ chối phải ghi lý do để sinh viên chụp lại');
      return;
    }
    setState(() {
      _busy = true;
      _reasonError = null;
      _error = null;
    });
    try {
      await widget.api.post('/faces/${widget.item['id']}/review',
          data: {'decision': approve ? 'approve' : 'reject', if (!approve) 'reason': reason});
      widget.onDecided(approve
          ? 'Đã duyệt khuôn mặt của ${widget.item['full_name']}'
          : 'Đã từ chối, ${widget.item['full_name']} sẽ thấy lý do');
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final update = it['is_update'] == true;
    final classes = (it['classes'] as List?)?.join(', ') ?? '';
    final sent = DateTime.parse('${it['created_at']}').toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return NeoCard(
      padding: EdgeInsets.zero,
      radius: 20,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            InitialsAvatar('${it['full_name']}', size: 56),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${it['full_name']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text)),
              Text(
                  '${it['student_code'] ?? it['username']}${classes.isEmpty ? '' : ' · $classes'} · gửi '
                  '${two(sent.hour)}:${two(sent.minute)}, ${two(sent.day)}/${two(sent.month)}/${sent.year}',
                  style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
            ]),
            Pill(update ? 'Cập nhật khuôn mặt' : 'Đăng ký lần đầu',
                bg: update ? AppColors.cardBorder : AppColors.primarySoft,
                fg: update ? AppColors.textSecondary : AppColors.primary, fontSize: 13,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
          ]),
        ),
        const Divider(height: 1, color: AppColors.cardBorder),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_photos == null && _error == null)
              const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
            else if (_photos != null)
              LayoutBuilder(builder: (context, c) {
                final w = ((c.maxWidth - 14 * 2) / 3).clamp(100.0, 220.0);
                return Wrap(spacing: 14, runSpacing: 14, children: [
                  for (final (i, p) in _photos!.indexed)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: w,
                        height: w * 4 / 3,
                        child: Stack(fit: StackFit.expand, children: [
                          Image.memory(p, fit: BoxFit.cover, semanticLabel: 'Ảnh đăng ký ${i + 1}',
                              errorBuilder: (_, _, _) => const ColoredBox(
                                  color: Color(0xFF111A2E),
                                  child: Center(child: Text('Ảnh lỗi', style: TextStyle(color: AppColors.heroText))))),
                          Positioned(
                            left: 10,
                            top: 10,
                            child: Pill(_poses[i], bg: const Color(0xB80F172A), fg: Colors.white, fontSize: 12),
                          ),
                        ]),
                      ),
                    ),
                ]);
              }),
            const SizedBox(height: 20),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final (label, value) in const [
                ('Một khuôn mặt mỗi ảnh', 'Server đã kiểm tra'),
                ('Ánh sáng và độ nét', 'Server đã kiểm tra'),
                ('Người thật (liveness)', 'Không phát hiện giả mạo'),
                ('Cùng một người', 'Các ảnh giống nhau'),
              ])
                Container(
                  width: 250,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.inputFill, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(color: AppColors.presentSoft, shape: BoxShape.circle),
                      child: const Icon(Icons.check, size: 14, color: Color(0xFF059669)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
                        Text(value, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ]),
                    ),
                  ]),
                ),
            ]),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              decoration: BoxDecoration(border: Border.all(color: AppColors.inputBorder), borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, top: 4),
                  child: Text('Bạn đối chiếu bằng mắt', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                CheckboxListTile(
                  value: _matchesCard,
                  onChanged: (v) => setState(() => _matchesCard = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: const Text('Khớp với ảnh thẻ sinh viên hoặc hồ sơ của trường', style: TextStyle(fontSize: 14)),
                ),
                CheckboxListTile(
                  value: _notReplay,
                  onChanged: (v) => setState(() => _notReplay = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: const Text('Không phải ảnh chụp lại từ màn hình hay giấy in', style: TextStyle(fontSize: 14)),
                ),
              ]),
            ),
            const SizedBox(height: 18),
            const Text.rich(TextSpan(children: [
              TextSpan(text: 'Lý do từ chối ', style: TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: '(bắt buộc khi từ chối)', style: TextStyle(color: AppColors.textMuted)),
            ]), style: TextStyle(fontSize: 14)),
            const SizedBox(height: 6),
            TextField(
              controller: _reason,
              decoration: InputDecoration(hintText: 'VD: Ảnh không khớp thẻ sinh viên', errorText: _reasonError),
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorNote(_error!)],
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: const BoxDecoration(
            color: AppColors.inputFill,
            border: Border(top: BorderSide(color: AppColors.cardBorder)),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
          ),
          child: Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 10, children: [
            const Text('Lượt xem được ghi nhật ký · ảnh bị xóa ngay sau khi quyết định',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 46),
                foregroundColor: const Color(0xFFE11D48),
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFFECDD3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _busy ? null : () => _decide(false),
              child: const Text('Từ chối', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 46),
                backgroundColor: const Color(0xFF059669),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _busy || !_matchesCard || !_notReplay || _photos == null ? null : () => _decide(true),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Duyệt khuôn mặt'),
            ),
          ]),
        ),
      ]),
    );
  }
}
