import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'services/app_state.dart';
import 'services/backend_api.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        Provider<BackendApi>(create: (_) => createBackendApi()),
        ChangeNotifierProvider(
          create: (ctx) => AppState(ctx.read<BackendApi>())..init(),
        ),
      ],
      child: const PoliceDogApp(),
    ),
  );
}

class PoliceDogApp extends StatelessWidget {
  const PoliceDogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '警犬姿态识别',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A237E)),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
