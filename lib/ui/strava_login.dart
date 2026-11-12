import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../state/app_state.dart';
import 'theme.dart';

/// Вход в Strava во встроенном браузере. После входа открываем тепловую карту:
/// Strava выдаёт cookie доступа к детальным тайлам, их и сохраняем.
class StravaLoginScreen extends StatefulWidget {
  const StravaLoginScreen({super.key, required this.state});

  final AppState state;

  @override
  State<StravaLoginScreen> createState() => _StravaLoginScreenState();
}

class _StravaLoginScreenState extends State<StravaLoginScreen> {
  static const _heatmapUrl = 'https://www.strava.com/maps/global-heatmap';
  InAppWebViewController? _c;
  bool _done = false;
  String _hint = 'Войдите в свой аккаунт Strava (бесплатный подходит).';

  Future<bool> _tryGrab() async {
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri('https://content-a.strava.com/identified/globalheat/all/hot/12/2476/1280.png'),
    );
    final hasSig = cookies.any((c) => c.name.toString().startsWith('CloudFront-'));
    if (!hasSig) return false;
    final header = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    widget.state.updateSettings((x) {
      x.stravaCookie = header;
      x.stravaCookieDate = DateTime.now().toIso8601String();
      x.strava = true;
    });
    return true;
  }

  Future<void> _onLoadStop(InAppWebViewController c, WebUri? url) async {
    if (_done) return;
    final u = url?.toString() ?? '';
    if (u.contains('/login') || u.contains('/session') || u.contains('/register') || u.contains('/onboarding')) {
      return;
    }
    if (!u.contains('heatmap')) {
      setState(() => _hint = 'Открываю тепловую карту…');
      await c.loadUrl(urlRequest: URLRequest(url: WebUri(_heatmapUrl)));
      return;
    }
    // Тайлы с cookie грузятся не сразу — несколько попыток.
    for (var i = 0; i < 10 && mounted; i++) {
      if (await _tryGrab()) {
        _done = true;
        if (mounted) {
          toast(context, 'Strava подключена');
          Navigator.pop(context);
        }
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (mounted) {
      setState(() => _hint = 'Подвигайте или приблизьте карту, затем нажмите «Готово».');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Вход в Strava'),
        actions: [
          TextButton(
            onPressed: () async {
              if (await _tryGrab()) {
                _done = true;
                if (context.mounted) {
                  toast(context, 'Strava подключена');
                  Navigator.pop(context);
                }
              } else {
                await _c?.loadUrl(urlRequest: URLRequest(url: WebUri(_heatmapUrl)));
                if (context.mounted) toast(context, 'Сначала войдите и дождитесь тепловой карты');
              }
            },
            child: const Text('Готово'),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: C.card,
            padding: const EdgeInsets.all(12),
            child: Text(_hint, style: const TextStyle(color: C.text2)),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri('https://www.strava.com/login')),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                thirdPartyCookiesEnabled: true,
              ),
              onWebViewCreated: (c) => _c = c,
              onLoadStop: _onLoadStop,
            ),
          ),
        ],
      ),
    );
  }
}
