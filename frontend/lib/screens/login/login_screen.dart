import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/telegram/telegram_service.dart';
import 'widgets/google_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start periodic polling while on login screen
    _startPolling();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Immediately refresh when user returns from browser
      _refresh();
    }
  }

  void _startPolling() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _refresh();
    });
  }

  Future<void> _refresh() async {
    if (mounted) {
      await context.read<AuthProvider>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final telegramService = context.read<TelegramService>();
    final userData = telegramService.getUser();

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (userData['photo_url'] != null)
                CircleAvatar(
                  radius: 50,
                  backgroundImage: NetworkImage(userData['photo_url']),
                )
              else
                const CircleAvatar(
                  radius: 50,
                  child: Icon(Icons.person, size: 50),
                ),
              const SizedBox(height: 24),
              Text(
                "Hello, ${userData['first_name'] ?? 'User'}!",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                "Connect your calendar to find the best time for meetings with your group.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withOpacity(0.7),
                    ),
              ),
              const SizedBox(height: 48),
              if (authProvider.isLoading)
                const CircularProgressIndicator()
              else ...[
                GoogleButton(
                  onPressed: () {
                    telegramService.hapticFeedback();
                    authProvider.connectGoogle();
                  },
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () {
                    telegramService.hapticFeedback();
                    telegramService.close();
                  },
                  icon: const Icon(Icons.close, color: Colors.white70),
                  label: const Text(
                    "Close and return to bot",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
              if (authProvider.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Text(
                    "Error: ${authProvider.error}",
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
