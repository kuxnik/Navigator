import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'state/app_state.dart';
import 'ui/map_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final state = AppState();
  runApp(NavigatorApp(state: state));
  try {
    await WakelockPlus.enable(); // экран не гаснет, пока приложение открыто
  } catch (_) {}
  await state.init();
}

class NavigatorApp extends StatelessWidget {
  const NavigatorApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Навигатор',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _Startup(state: state),
    );
  }
}

/// Заставка с логотипом, пока загружаются карты и треки (не меньше 1,5 с).
class _Startup extends StatefulWidget {
  const _Startup({required this.state});

  final AppState state;

  @override
  State<_Startup> createState() => _StartupState();
}

class _StartupState extends State<_Startup> {
  bool _minTimePassed = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _minTimePassed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final ready = widget.state.ready && _minTimePassed;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: ready ? MapScreen(state: widget.state) : const SplashView(),
        );
      },
    );
  }
}

class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo_splash.png', height: 200, filterQuality: FilterQuality.high),
            const SizedBox(height: 24),
            const Text(
              'НАВИГАТОР',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 4, color: C.text2),
            ),
          ],
        ),
      ),
    );
  }
}
