import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import 'core/api/api_service.dart';
import 'core/telegram/telegram_service.dart';

import 'providers/auth_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/scheduler_provider.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/scheduler/scheduler_screen.dart';
import 'providers/group_provider.dart';
import 'providers/meeting_provider.dart';
import 'providers/availability_provider.dart';
import 'providers/language_provider.dart';
import 'providers/solo_provider.dart';
import 'providers/working_hours_notifier.dart';
import 'screens/settings/availability_settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  try {
    final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(currentTimeZone));
  } catch (e) {
    print('Could not get local timezone: $e');
  }

  final TelegramService telegramService = TelegramService();
  
  telegramService.init();
  final apiService = ApiService(telegramService);


  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: telegramService),
        Provider.value(value: apiService),

        ChangeNotifierProvider(
          create: (_) => LanguageProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(apiService, telegramService)..init(),
        ),
        ChangeNotifierProvider(
          create: (_) => SyncProvider(apiService),
        ),
        ChangeNotifierProvider(
          create: (context) => GroupProvider(
            context.read<ApiService>(),
            context.read<TelegramService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SchedulerProvider(apiService),
        ),
        ChangeNotifierProvider(
          create: (_) => MeetingProvider(apiService),
        ),
        ChangeNotifierProvider(
          create: (_) => AvailabilityProvider(apiService),
        ),
        ChangeNotifierProvider(
          create: (_) => SoloProvider(apiService),
        ),
        ChangeNotifierProvider(
          create: (_) => WorkingHoursNotifier(),
        ),
      ],
      child: const SmartSchedulerApp(),
    ),
  );
}

class SmartSchedulerApp extends StatefulWidget {
  const SmartSchedulerApp({super.key});

  @override
  State<SmartSchedulerApp> createState() => _SmartSchedulerAppState();
}

class _SmartSchedulerAppState extends State<SmartSchedulerApp> with WidgetsBindingObserver {
  void _parseDeepLink() async {
    final telegram = context.read<TelegramService>();
    final groupProvider = context.read<GroupProvider>();
    
    // Attempt detection multiple times as WebApp might not be ready immediately
    for (int i = 0; i < 5; i++) {
      if (groupProvider.chatId != null) break;
      
      String? startParam = telegram.getStartParam();
      if (startParam == null) {
        startParam = telegram.getStartParamFromUrl(Uri.base.toString());
      }
      
      if (startParam != null && startParam.startsWith("group_")) {
        final chatIdStr = startParam.replaceFirst("group_", "");
        final chatId = chatIdStr.startsWith("n") 
            ? chatIdStr.replaceFirst("n", "-")
            : chatIdStr;
            
        print("DEBUG: Deep link matched group: $chatId");
        groupProvider.setChatId(chatId);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Connected to group: $chatId"),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            )
          );
        }
        return;
      }
      await Future.delayed(Duration(milliseconds: 300 * (i + 1)));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _parseDeepLink());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh auth and sync status when user returns to app
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          context.read<AuthProvider>().init();
          context.read<SyncProvider>().sync(); // Also sync calendar on resume
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final router = GoRouter(
      initialLocation: '/login',
      refreshListenable: authProvider,
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/scheduler',
          builder: (context, state) => const SchedulerScreen(),
        ),
        GoRoute(
          path: '/availability',
          builder: (context, state) => const AvailabilitySettingsScreen(),
        ),
      ],
      redirect: (context, state) {
        final loggingIn = state.matchedLocation == '/login';

        if (authProvider.user == null) {
          return loggingIn ? null : '/login';
        }

        if (loggingIn) {
          return '/home';
        }

        return null;
      },
    );

    final isDark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;

    return MaterialApp.router(
      title: 'Smart Scheduler',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: ThemeMode.system, // Switch automatically between light and dark
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark, // Force brightness to dark even in light theme slot
        colorSchemeSeed: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
    );
  }
}
