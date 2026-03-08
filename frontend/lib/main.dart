import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/api/api_service.dart';
import 'core/telegram/telegram_service.dart';
import 'core/database/database_service.dart';
import 'providers/auth_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/scheduler_provider.dart';
import 'screens/login/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/scheduler/scheduler_screen.dart';
import 'providers/group_provider.dart';

void main() {
  final TelegramService telegramService = TelegramService();
  
  telegramService.init();
  final apiService = ApiService(telegramService);
  final databaseService = DatabaseService();

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: telegramService),
        Provider.value(value: apiService),
        Provider.value(value: databaseService),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(apiService, telegramService)..init(),
        ),
        ChangeNotifierProvider(
          create: (_) => SyncProvider(apiService, databaseService),
        ),
        ChangeNotifierProvider(
          create: (context) => GroupProvider(context.read<ApiService>()),
        ),
        ChangeNotifierProvider(
          create: (_) => SchedulerProvider(apiService),
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Parse deep link group context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final telegram = context.read<TelegramService>();
      String? startParam = telegram.getStartParam();
      
      print("DEBUG: Telegram startParam: $startParam");
      
      // Fallback to Uri.base if Telegram start_param is null (common on Desktop/Web)
      if (startParam == null) {
        final uri = Uri.base;
        print("DEBUG: URI.base: $uri");
        print("DEBUG: URI.queryParameters: ${uri.queryParameters}");
        print("DEBUG: URI.fragment: ${uri.fragment}");
        
        startParam = uri.queryParameters['startapp'];
        
        // Robust fragment parsing (HashStrategy support)
        if (startParam == null && uri.fragment.isNotEmpty) {
          // Case 1: #/?startapp=...
          // Case 2: #/scheduler?startapp=...
          final fragmentQueryIndex = uri.fragment.indexOf('?');
          if (fragmentQueryIndex != -1) {
            final fragmentQuery = uri.fragment.substring(fragmentQueryIndex + 1);
            final fragmentParts = Uri.splitQueryString(fragmentQuery);
            startParam = fragmentParts['startapp'];
          } else if (uri.fragment.contains('startapp=')) {
            // Case 3: #startapp=... (no question mark)
            final parts = Uri.splitQueryString(uri.fragment.startsWith('/') 
                ? uri.fragment.substring(1) 
                : uri.fragment);
            startParam = parts['startapp'];
          }
        }
      }

      print("DEBUG: Final extracted startParam: $startParam");

      if (startParam != null && startParam.startsWith("group_")) {
        final chatId = startParam.replaceFirst("group_", "");
        print("DEBUG: Setting chatId: $chatId");
        context.read<GroupProvider>().setChatId(chatId);
        
        // Also show a small snackbar for 1s to confirm to the user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Syncing with group: $chatId"),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          )
        );
      }
    });
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
      ],
      redirect: (context, state) {
        final loggingIn = state.matchedLocation == '/login';

        if (authProvider.user == null) {
          return loggingIn ? null : '/login';
        }

        // Check if user is connected to any calendar
        final isConnected = authProvider.isConnected || authProvider.isAppleConnected;
        if (!isConnected && state.matchedLocation != '/login') {
          return '/login'; // Force connection onboarding
        }

        if (loggingIn && isConnected) {
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
