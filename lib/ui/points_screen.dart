import 'package:flutter/material.dart';

import '../data/models.dart';
import '../nav/geo.dart';
import '../state/app_state.dart';
import 'theme.dart';

/// Новая точка: название + координаты. Кнопки «Сохранить» и «Вести к точке».
Future<void> showPointDialog(BuildContext context, AppState s, {required double lat, required double lon}) async {
  final name = TextEditingController(text: s.nextPointName());
  final latC = TextEditingController(text: fmtCoord(lat));
  final lonC = TextEditingController(text: fmtCoord(lon));
  final res = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Новая точка'),
      content: _PointFields(name: name, lat: latC, lon: lonC),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Отмена')),
        TextButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Сохранить')),
        FilledButton(onPressed: () => Navigator.pop(c, 'target'), child: const Text('Вести к ней')),
      ],
    ),
  );
  if (res == null) return;
  final la = parseCoord(latC.text);
  final lo = parseCoord(lonC.text);
  if (la == null || lo == null || la.abs() > 90 || lo.abs() > 180) {
    toast(context, 'Неверные координаты');
    return;
  }
  final n = name.text.trim().isEmpty ? s.nextPointName() : name.text.trim();
  s.addPoint(n, la, lo, asTarget: res == 'target');
}

/// Редактор существующей точки.
Future<void> openPointEditor(BuildContext context, AppState s, Waypoint w) async {
  final name = TextEditingController(text: w.name);
  final latC = TextEditingController(text: fmtCoord(w.lat));
  final lonC = TextEditingController(text: fmtCoord(w.lon));
  final p = s.pos;
  final info = p == null ? 'WGS-84, градусы' : 'WGS-84, градусы · ${fmtDist(distanceM(p, w.pos))}, азимут ${bearingDeg(p, w.pos).round()}°';
  final isTarget = s.settings.targetId == w.id;
  final res = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.bg,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(c).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Точка', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _PointFields(name: name, lat: latC, lon: lonC),
            const SizedBox(height: 6),
            Text(info, style: const TextStyle(fontSize: 12, color: C.text2)),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: C.accent,
                foregroundColor: const Color(0xFF1A1406),
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => Navigator.pop(c, isTarget ? 'untarget' : 'target'),
              icon: const Icon(Icons.navigation),
              label: Text(isTarget ? 'Перестать вести' : 'Вести к точке',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => Navigator.pop(c, 'save'),
                  child: const Text('Сохранить'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 56,
                height: 48,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: const Color(0xFFFF8A7F)),
                  onPressed: () => Navigator.pop(c, 'delete'),
                  child: const Icon(Icons.delete_outline),
                ),
              ),
            ]),
          ],
        ),
      ),
    ),
  );
  if (res == null) return;
  if (res == 'delete') {
    s.deletePoint(w);
    return;
  }
  final la = parseCoord(latC.text);
  final lo = parseCoord(lonC.text);
  if (la != null && lo != null && la.abs() <= 90 && lo.abs() <= 180) {
    s.updatePoint(w, name: name.text.trim().isEmpty ? w.name : name.text.trim(), lat: la, lon: lo);
  } else {
    toast(context, 'Координаты не изменены: неверный формат');
  }
  if (res == 'target') s.setTarget(w);
  if (res == 'untarget') s.setTarget(null);
}

class _PointFields extends StatelessWidget {
  const _PointFields({required this.name, required this.lat, required this.lon});

  final TextEditingController name;
  final TextEditingController lat;
  final TextEditingController lon;

  @override
  Widget build(BuildContext context) {
    const kb = TextInputType.numberWithOptions(decimal: true, signed: true);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: lat, keyboardType: kb, decoration: const InputDecoration(labelText: 'Широта'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: lon, keyboardType: kb, decoration: const InputDecoration(labelText: 'Долгота'))),
        ]),
      ],
    );
  }
}

class PointsScreen extends StatelessWidget {
  const PointsScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final p = state.pos;
        final list = List.of(state.points);
        if (p != null) {
          list.sort((a, b) => distanceM(p, a.pos).compareTo(distanceM(p, b.pos)));
        }
        return Scaffold(
          appBar: AppBar(
            title: const Text('Точки'),
            actions: [
              IconButton(
                tooltip: 'Добавить по координатам',
                icon: const Icon(Icons.add),
                onPressed: () => showPointDialog(context, state,
                    lat: p?.latitude ?? 55.75580, lon: p?.longitude ?? 37.61730),
              ),
            ],
          ),
          body: list.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Точек пока нет.\nДолгое нажатие на карте или кнопка «+» добавят точку.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: C.text2),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final w = list[i];
                    final sel = w.id == state.settings.targetId;
                    final d = p == null ? null : distanceM(p, w.pos);
                    final b = p == null ? null : bearingDeg(p, w.pos);
                    return Material(
                      color: sel ? const Color(0xFF2A2310) : C.card,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: sel ? C.accent : C.cardBorder),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => openPointEditor(context, state, w),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(children: [
                            Icon(Icons.location_on, color: sel ? C.accent : C.blue),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(w.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                  Text('${fmtCoord(w.lat)}, ${fmtCoord(w.lon)}',
                                      style: const TextStyle(fontSize: 12, color: C.text2)),
                                ],
                              ),
                            ),
                            if (d != null && b != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(fmtDist(d), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                  Row(mainAxisSize: MainAxisSize.min, children: [
                                    Transform.rotate(
                                      angle: deg2rad(b),
                                      child: const Icon(Icons.navigation, size: 12, color: C.text2),
                                    ),
                                    const SizedBox(width: 4),
                                    Text('${b.round()}°', style: const TextStyle(fontSize: 12, color: C.text2)),
                                  ]),
                                ],
                              ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
