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
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) => state.ready
            ? MapScreen(state: state)
            : const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
  }
}
