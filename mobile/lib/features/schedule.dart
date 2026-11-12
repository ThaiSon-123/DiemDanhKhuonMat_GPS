import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/api_error.dart';
import '../ui/neo.dart';
import '../ui/neo_parts.dart';
import '../ui/theme.dart';
import 'admin/admin_widgets.dart';

/// 1 = Thứ Hai … 7 = Chủ nhật (giống `DateTime.weekday` và cột `class_schedules.weekday`).
const weekdayNames = {1: 'Thứ Hai', 2: 'Thứ Ba', 3: 'Thứ Tư', 4: 'Thứ Năm', 5: 'Thứ Sáu', 6: 'Thứ Bảy', 7: 'Chủ nhật'};

/// Một buổi trong lịch hằng tuần của một lớp.
class Slot {
  const Slot(this.cls, this.weekday, this.start, this.end, this.room);
  final Map<String, dynamic> cls;
  final int weekday;
  final String start; // "HH:MM"
  final String end;
  final String? room;

  String get time => '$start–$end';
  String get where => room == null || room!.isEmpty ? '' : ' · $room';

  DateTime on(DateTime day, String hhmm) {
    final p = hhmm.split(':');
    return DateTime(day.year, day.month, day.day, int.parse(p[0]), int.parse(p[1]));
  }
}

List<Slot> slotsOf(List<Map<String, dynamic>> classes) => [
      for (final c in classes)
        for (final s in (c['schedules'] as List? ?? const []))
          Slot(c, (s as Map)['weekday'] as int, '${s['start']}', '${s['end']}', s['room'] as String?),
    ]..sort((a, b) => a.weekday != b.weekday ? a.weekday.compareTo(b.weekday) : a.start.compareTo(b.start));

/// Buổi học hôm nay (theo giờ máy).
List<Slot> todaySlots(List<Map<String, dynamic>> classes, {DateTime? now}) {
  final d = now ?? DateTime.now();
  return [for (final s in slotsOf(classes)) if (s.weekday == d.weekday) s];
}

/// Buổi sắp bắt đầu trong [within] tới (để nhắc giờ).
List<Slot> upcomingSlots(List<Map<String, dynamic>> classes, {DateTime? now, Duration within = const Duration(minutes: 30)}) {
  final t = now ?? DateTime.now();
  return [
    for (final s in todaySlots(classes, now: t))
      if (!s.on(t, s.start).isBefore(t) && s.on(t, s.start).difference(t) <= within) s,
  ];
}

/// Thẻ "Lịch hôm nay" + nút xem cả tuần, dùng ở trang chủ sinh viên.
class TodaySchedule extends StatelessWidget {
  const TodaySchedule({super.key, required this.classes});
  final List<Map<String, dynamic>> classes;

  @override
  Widget build(BuildContext context) {
    final all = slotsOf(classes);
    if (all.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    final today = [for (final s in all) if (s.weekday == now.weekday) s];
    return NeoCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.today, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Lịch hôm nay · ${weekdayNames[now.weekday]}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
          ),
          TextButton(onPressed: () => showWeekSchedule(context, all), child: const Text('Cả tuần')),
        ]),
        if (today.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('Hôm nay không có lịch học.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ),
        for (final s in today) _SlotRow(s, now: now),
      ]),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow(this.s, {this.now});
  final Slot s;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final t = now;
    final live = t != null && !t.isBefore(s.on(t, s.start)) && t.isBefore(s.on(t, s.end));
    final done = t != null && !t.isBefore(s.on(t, s.end));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(
          width: 96,
          child: Text(s.time, style: mono.copyWith(fontSize: 12, fontWeight: FontWeight.w700,
              color: done ? AppColors.textMuted : AppColors.text)),
        ),
        CodeChip('${s.cls['code']}'),
        const SizedBox(width: 8),
        Expanded(
          child: Text('${s.cls['name']}${s.where}', overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: done ? AppColors.textMuted : AppColors.textSecondary)),
        ),
        if (live)
          Pill('Đang học', bg: AppColors.presentSoft, fg: AppColors.presentText, border: AppColors.presentBorder,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1)),
      ]),
    );
  }
}

/// Bảng lịch học cả tuần.
Future<void> showWeekSchedule(BuildContext context, List<Slot> slots) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 18, 16, 16), children: [
            const Text('Lịch học trong tuần', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 12),
            for (final d in weekdayNames.keys)
              if (slots.any((s) => s.weekday == d)) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                  child: Text(weekdayNames[d]!.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      letterSpacing: 0.8, color: d == DateTime.now().weekday ? AppColors.primary : AppColors.textMuted)),
                ),
                NeoCard(
                  radius: 18,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: Column(children: [for (final s in slots.where((s) => s.weekday == d)) _SlotRow(s)]),
                ),
                const SizedBox(height: 6),
              ],
          ]),
        ),
      ),
    );

/// Một dòng tóm tắt lịch của một lớp, vd "Thứ Ba 07:00–09:30 · D9-301; Thứ Sáu 13:00–15:00".
String scheduleSummary(Map<String, dynamic> cls) => [
      for (final s in slotsOf([cls])) '${weekdayNames[s.weekday]} ${s.time}${s.where}',
    ].join('; ');

/// Quản trị nhập lịch học của một lớp (trang Lớp). GET/POST /admin/classes/{id}/schedules, DELETE /admin/schedules/{id}.
class ScheduleEditor extends StatefulWidget {
  const ScheduleEditor({super.key, required this.api, required this.classId});
  final ApiClient api;
  final int classId;

  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  List<Map<String, dynamic>>? _rows;
  int _weekday = 1;
  TimeOfDay _start = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 9, minute: 30);
  final _room = TextEditingController();
  String? _error;

  String get _path => '/admin/classes/${widget.classId}/schedules';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _room.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.get(_path) as List;
      if (mounted) setState(() => _rows = [for (final x in r) Map<String, dynamic>.from(x as Map)]);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  static String _hm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _add() async {
    setState(() => _error = null);
    try {
      await widget.api.post(_path, data: {'weekday': _weekday, 'start_time': _hm(_start), 'end_time': _hm(_end),
        'room': _room.text.trim().isEmpty ? null : _room.text.trim()});
      _room.clear();
      await _load();
    } on ApiError catch (e) {
      final d = e.details;
      final msg = d is List && d.isNotEmpty ? '${(d.first as Map)['msg']}' : e.message; // vd "Giờ kết thúc phải sau…"
      if (mounted) setState(() => _error = msg);
    }
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    try {
      await widget.api.delete('/admin/schedules/${r['id']}');
      await _load();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pick(bool start) async {
    final t = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (t != null) setState(() => start ? _start = t : _end = t);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return NeoCard(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Lịch học hằng tuần', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(height: 4),
        const Text('Sinh viên xem lịch và được nhắc 30 phút trước giờ học.',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        const SizedBox(height: 12),
        if (rows == null && _error == null) const LinearProgressIndicator(),
        if (rows != null && rows.isEmpty)
          const Text('Chưa có lịch.', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        for (final r in rows ?? const <Map<String, dynamic>>[])
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.cardBorder))),
            child: Row(children: [
              SizedBox(width: 90, child: Text(weekdayNames[r['weekday']]!,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text))),
              Text('${'${r['start_time']}'.substring(0, 5)}–${'${r['end_time']}'.substring(0, 5)}',
                  style: mono.copyWith(fontSize: 13, color: AppColors.text)),
              const SizedBox(width: 12),
              Expanded(child: Text('${r['room'] ?? ''}', style: const TextStyle(fontSize: 13, color: AppColors.textMuted))),
              IconButton(tooltip: 'Xóa', onPressed: () => _delete(r),
                  icon: const Icon(Icons.delete_outline, size: 19, color: AppColors.absentText)),
            ]),
          ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 150,
            child: AdminSelect<int>(
              label: 'Thứ',
              value: _weekday,
              options: {for (final e in weekdayNames.entries) e.key: e.value},
              onChanged: (v) => setState(() => _weekday = v ?? 1),
            ),
          ),
          OutlinedButton.icon(style: adminOutlinedStyle(), onPressed: () => _pick(true),
              icon: const Icon(Icons.schedule, size: 16), label: Text('Từ ${_hm(_start)}')),
          OutlinedButton.icon(style: adminOutlinedStyle(), onPressed: () => _pick(false),
              icon: const Icon(Icons.schedule, size: 16), label: Text('Đến ${_hm(_end)}')),
          SizedBox(
            width: 140,
            child: TextField(controller: _room, style: const TextStyle(fontSize: 14),
                decoration: adminFieldDecoration('Phòng, vd D9-301')),
          ),
          SizedBox(height: 46, child: adminPrimaryButton('Thêm lịch', Icons.add, _add)),
        ]),
        if (_error != null) ...[const SizedBox(height: 10), ErrorNote(_error!)],
      ]),
    );
  }
}
