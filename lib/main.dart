import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme.dart';
import 'data/app_store.dart';
import 'firebase_options.dart';
import 'screens/auth_screens.dart';
import 'screens/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AppStore.instance.init();
  runApp(const TaskFlowApp());
}

class TaskFlowApp extends StatelessWidget {
  const TaskFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaskFlow',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: ListenableBuilder(
        listenable: AppStore.instance,
        builder: (context, _) {
          final store = AppStore.instance;
          if (store.currentUser != null) return const MainShell();
          if (!store.seenOnboarding) return const OnboardingScreen();
          return const LoginScreen();
        },
      ),
    );
  }
}
