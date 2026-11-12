import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../nav/geo.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'track_screen.dart';

Future<String?> _pickFile() async {
  final r = await FilePicker.platform.pickFiles(type: FileType.any);
  if (r == null || r.files.isEmpty) return null;
  return r.files.single.path;
}

Future<T?> _withProgress<T>(BuildContext context, String text, Future<T> Function() job) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 16),
          Expanded(child: Text(text)),
        ]),
      ),
    ),
  );
  try {
    return await job();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

Future<void> importMapFlow(BuildContext context, AppState s) async {
  final path = await _pickFile();
  if (path == null) return;
  if (!path.toLowerCase().endsWith('.mbtiles')) {
    toast(context, 'Нужен файл .mbtiles');
    return;
  }
  try {
    final m = await _withProgress(context, 'Копирую карту…', () => s.importMap(path));
    if (m != null) toast(context, 'Карта добавлена: ${m.name}');
  } catch (e) {
    toast(context, 'Не удалось открыть карту: $e');
  }
}

Future<void> importTrackFlow(BuildContext context, AppState s) async {
  final path = await _pickFile();
  if (path == null) return;
  final low = path.toLowerCase();
  if (!low.endsWith('.gpx') && !low.endsWith('.kml')) {
    toast(context, 'Нужен файл .gpx или .kml');
    return;
  }
  try {
    final r = await _withProgress(context, 'Читаю файл…', () => s.importGeoFile(path));
    if (r != null) toast(context, 'Импортировано: треков ${r.$1}, точек ${r.$2}');
  } catch (e) {
    toast(context, 'Не удалось прочитать файл: $e');
  }
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final s = state;
        return Scaffold(
          appBar: AppBar(title: const Text('Карты и треки')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              const _Header('Офлайн-карты'),
              _MapTile(
                title: 'OSM онлайн',
                subtitle: 'нужен интернет · запасной вариант',
                selected: s.settings.mapId == null || (s.currentMap == null && s.settings.mapId != kSatMapId),
                onTap: () => s.selectMap(null),
              ),
              _MapTile(
                title: 'Спутник онлайн (Esri)',
                subtitle: 'нужен интернет · видно накатанные колеи',
                selected: s.settings.mapId == kSatMapId,
                onTap: () => s.updateSettings((x) => x.mapId = kSatMapId),
              ),
              for (final m in s.maps)
                _MapTile(
                  title: m.name,
                  subtitle: '${m.sizeText} · масштабы ${m.minZoom}–${m.maxZoom}',
                  selected: s.currentMap?.id == m.id,
                  onTap: () => s.selectMap(m),
                  onDelete: () async {
                    final ok = await _confirm(context, 'Удалить карту «${m.name}»?');
                    if (ok) await s.deleteMap(m);
                  },
                ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => importMapFlow(context, s),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Добавить .mbtiles из «Файлов»'),
              ),
              const SizedBox(height: 20),
              const _Header('Треки на карте'),
              if (s.tracks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Треков пока нет. Запишите свой или импортируйте GPX/KML.',
                      style: TextStyle(color: C.text2)),
                ),
              for (final t in s.tracks) _TrackTile(state: s, track: t),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () => importTrackFlow(context, s),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Импорт GPX / KML'),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<bool> _confirm(BuildContext context, String text) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить')),
      ],
    ),
  );
  return ok == true;
}

Future<void> shareTrack(AppState s, Track t) async {
  await SharePlus.instance.share(ShareParams(files: [XFile(s.storage.trackPath(t))], text: t.name));
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.text2, letterSpacing: 0.8)),
      );
}

class _MapTile extends StatelessWidget {
  const _MapTile({required this.title, required this.subtitle, required this.selected, required this.onTap, this.onDelete});

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? const Color(0xFF132A40) : C.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? C.blue : C.cardBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onDelete,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? C.blue : C.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: C.text2)),
                ]),
              ),
              if (onDelete != null)
                IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline, color: C.text2)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.state, required this.track});

  final AppState state;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final st = track.stats;
    final meta = [
      track.source == 'rec' ? 'записан' : 'импорт',
      fmtDist(st.distance),
      if (st.total != null) fmtDuration(st.total!),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: C.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: C.cardBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TrackScreen(state: state, track: track)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            child: Row(children: [
              Container(
                width: 6,
                height: 30,
                decoration: BoxDecoration(color: Color(track.color), borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(meta, style: const TextStyle(fontSize: 12, color: C.text2)),
                ]),
              ),
              Switch(
                value: track.visible,
                onChanged: (v) => state.setTrackVisible(track, v),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
