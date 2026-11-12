import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'library_screen.dart';
import 'strava_login.dart';
import 'theme.dart';

void showLayersSheet(BuildContext context, AppState s) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: C.bg,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => ListenableBuilder(
      listenable: Listenable.merge([s, s.overpass]),
      builder: (c, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Слои карты', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              _box(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(Icons.map_outlined, color: C.text2),
                  title: const Text('Подложка', style: TextStyle(fontSize: 12, color: C.text2)),
                  subtitle: Text(s.baseMapName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.text)),
                  trailing: const Icon(Icons.chevron_right, color: C.text2),
                  onTap: () {
                    Navigator.pop(c);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => LibraryScreen(state: s)));
                  },
                ),
              ),
              const SizedBox(height: 8),
              _box(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      secondary: const Icon(Icons.alt_route, color: Color(0xFFFF6B4A)),
                      title: const Row(children: [
                        Flexible(child: Text('Грунтовки по проходимости', style: TextStyle(fontWeight: FontWeight.w600))),
                        SizedBox(width: 8),
                        _Badge('онлайн', Color(0xFF33264A), Color(0xFFD9B8FF)),
                      ]),
                      subtitle: Text(
                        s.overpass.loading
                            ? 'загружаю дороги для этого места…'
                            : (s.overpass.error ?? 'дороги-«грунтовки» из OSM, видны с масштаба 12 · ${s.overpass.ways.length} шт.'),
                        style: TextStyle(fontSize: 12, color: s.overpass.error != null ? C.red : C.text2),
                      ),
                      value: s.settings.osmGrades,
                      onChanged: (v) => s.updateSettings((x) => x.osmGrades = v),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 12, 12),
                      child: Wrap(spacing: 14, runSpacing: 6, children: [
                        _Legend(Color(0xFF5FD38D), 'любая машина'),
                        _Legend(Color(0xFFFFB020), 'кроссовер'),
                        _Legend(Color(0xFFFF6B4A), 'джип', dashed: true),
                        _Legend(Color(0xFFD9B98A), 'нет данных'),
                      ]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _box(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      secondary: const Icon(Icons.local_fire_department, color: Color(0xFFFF8A3D)),
                      title: const Row(children: [
                        Flexible(child: Text('Тепловая карта Strava', style: TextStyle(fontWeight: FontWeight.w600))),
                        SizedBox(width: 8),
                        _Badge('онлайн', Color(0xFF33264A), Color(0xFFD9B8FF)),
                      ]),
                      subtitle: Text(
                        s.settings.stravaCookie == null
                            ? 'нужен вход в Strava (бесплатный аккаунт)'
                            : 'где ездили и ходили люди со Strava · вход ${_date(s.settings.stravaCookieDate)}',
                        style: const TextStyle(fontSize: 12, color: C.text2),
                      ),
                      value: s.settings.strava && s.settings.stravaCookie != null,
                      onChanged: s.settings.stravaCookie == null ? null : (v) => s.updateSettings((x) => x.strava = v),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(c);
                          Navigator.push(context, MaterialPageRoute(builder: (_) => StravaLoginScreen(state: s)));
                        },
                        icon: const Icon(Icons.login, size: 18),
                        label: Text(s.settings.stravaCookie == null ? 'Войти в Strava' : 'Войти заново (если карта пропала)'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _box(
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  secondary: const Icon(Icons.timeline, color: C.purple),
                  title: const Row(children: [
                    Flexible(child: Text('Здесь кто-то был', style: TextStyle(fontWeight: FontWeight.w600))),
                    SizedBox(width: 8),
                    _Badge('онлайн', Color(0xFF33264A), Color(0xFFD9B8FF)),
                  ]),
                  subtitle: const Text('публичные GPS-треки OpenStreetMap, все виды транспорта',
                      style: TextStyle(fontSize: 12, color: C.text2)),
                  value: s.settings.osmTraces,
                  onChanged: (v) => s.updateSettings((x) => x.osmTraces = v),
                ),
              ),
              const SizedBox(height: 8),
              _box(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      secondary: const Icon(Icons.route, color: C.blue),
                      title: const Text('Мои и импортированные', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${s.tracks.where((t) => t.visible).length} из ${s.tracks.length} треков включено',
                          style: const TextStyle(fontSize: 12, color: C.text2)),
                      value: s.settings.mineLayer,
                      onChanged: (v) => s.updateSettings((x) => x.mineLayer = v),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: FilterChip(
                        selected: s.settings.carOnly,
                        onSelected: (v) => s.updateSettings((x) => x.carOnly = v),
                        label: const Text('только на машине, быстрее 15 км/ч'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _box(
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  secondary: const Icon(Icons.straighten, color: C.text),
                  title: const Text('Линейка по курсу', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('длина подбирается по масштабу, точки — каждая 1/10',
                      style: TextStyle(fontSize: 12, color: C.text2)),
                  value: s.settings.ruler,
                  onChanged: (v) => s.updateSettings((x) => x.ruler = v),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _box({required Widget child}) => Container(
      decoration: BoxDecoration(
        color: C.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: C.cardBorder),
      ),
      child: child,
    );

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.bg, this.fg);

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
      );
}

class _Legend extends StatelessWidget {
  const _Legend(this.color, this.text, {this.dashed = false});

  final Color color;
  final String text;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < (dashed ? 2 : 1); i++)
            Container(
              width: dashed ? 8 : 20,
              height: 4,
              margin: EdgeInsets.only(right: dashed ? 4 : 0),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
            ),
        ]),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFFD5DAE0))),
      ]);
}

String _date(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  if (d == null) return '—';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
}
