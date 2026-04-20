import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:echoscribe/theme.dart';
import 'package:echoscribe/pages/home_page.dart';
import 'package:echoscribe/widgets/iphone_web_shell.dart';
import 'package:echoscribe/services/service_locator.dart';

/// EchoScribe entry point with Jetpack/Flutter edge-to-edge enabled.
/// - Ensures bindings are initialized before touching SystemChrome.
/// - Enables edge-to-edge so Flutter layouts manage safe areas themselves.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ServiceLocator().init();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EchoScribe',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      // Keep your shell; pages should handle SafeArea/Insets explicitly.
      builder: (context, child) => IPhoneWebShell(
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomePage(),
    );
  }
}
