import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/availability_provider.dart';
import '../../providers/language_provider.dart';
import '../../providers/solo_provider.dart'; // Added
import '../../models/meeting.dart';
import 'widgets/solo_dashboard.dart'; // Added

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final TextEditingController _groupController = TextEditingController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MeetingProvider>().fetchMyMeetings();
    });
    // Auto-refresh every 30s so participants see new invites without manual pull-to-refresh
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        context.read<MeetingProvider>().fetchMyMeetings();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh when app comes back to foreground (e.g. user taps Telegram bot link)
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<MeetingProvider>().fetchMyMeetings();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _groupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final groupProvider = context.watch<GroupProvider>();
    final meetingProvider = context.watch<MeetingProvider>();
    final langProvider = context.watch<LanguageProvider>();
    final user = authProvider.user;

    return Scaffold(
      appBar: AppBar(
        title: Text(langProvider.translate('app_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              authProvider.init();
              groupProvider.syncWithGroup();
              meetingProvider.fetchMyMeetings();
            },
          ),
          IconButton(
            icon: const Icon(Icons.language),
            onPressed: () => _showLanguagePicker(context, langProvider),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => authProvider.logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await authProvider.init();
          await groupProvider.syncWithGroup();
          await meetingProvider.fetchMyMeetings();
          await context.read<SoloProvider>().fetchSoloSlots(); // Added
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Header
              Row(
                children: [
                   CircleAvatar(
                     radius: 25,
                     backgroundImage: (user?.photoUrl != null && user!.photoUrl!.isNotEmpty) 
                         ? NetworkImage(user.photoUrl!) : null,
                     child: (user?.photoUrl == null || user!.photoUrl!.isEmpty) 
                         ? const Icon(Icons.person, size: 25) : null,
                   ),
                   const SizedBox(width: 16),
                   Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Text(
                         "${langProvider.translate('welcome')}, ${user?.firstName ?? 'Пользователь'}!",
                         style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                       ),
                       Text(
                         user?.username != null ? "@${user!.username}" : langProvider.translate('setup_profile'),
                         style: const TextStyle(color: Colors.grey),
                       ),
                     ],
                   ),
                ],
              ),
              const SizedBox(height: 24),

              // Solo Dashboard (My Schedule)
              const SoloDashboard(),

              const SizedBox(height: 32),

              // Meetings & Invites Section
              _buildMeetingsSection(meetingProvider, langProvider),
              
              const SizedBox(height: 32),

              // Active Sync Section
              Text(
                langProvider.translate('group_sync'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildGroupSyncSection(groupProvider, authProvider, langProvider),

              const SizedBox(height: 32),

              // My Calendars Section
              Text(
                langProvider.translate('connected_calendars'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildCalendarsSection(authProvider),
              
              const SizedBox(height: 32),

              if (meetingProvider.meetings.isEmpty && !meetingProvider.isLoading)
                Text(
                  langProvider.translate('no_meetings'),
                  style: const TextStyle(color: Colors.grey),
                ),

              const SizedBox(height: 32),
              _buildQuickActions(context, authProvider, syncProvider, groupProvider, langProvider),
              
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, LanguageProvider lang) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Text("🇷🇺", style: TextStyle(fontSize: 24)),
              title: const Text("Русский"),
              onTap: () {
                lang.setLocale('ru');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Text("🇺🇸", style: TextStyle(fontSize: 24)),
              title: const Text("English"),
              onTap: () {
                lang.setLocale('en');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Text("🇺🇦", style: TextStyle(fontSize: 24)),
              title: const Text("Українська"),
              onTap: () {
                lang.setLocale('uk');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarsSection(AuthProvider auth) {
    final connections = auth.user?.connections ?? [];
    
    return Column(
      children: [
        if (connections.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text("Нет подключенных календарей", style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
        ...connections.map((conn) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              conn.provider == 'google'
                  ? Icons.mail
                  : conn.provider == 'outlook'
                      ? Icons.calendar_month
                      : Icons.apple,
              color: conn.provider == 'google'
                  ? Colors.red
                  : conn.provider == 'outlook'
                      ? const Color(0xFF0078D4) // Microsoft blue
                      : Colors.grey,
            ),
            title: Text(conn.email ?? "Подключено"),
            subtitle: Text(conn.status == 'active' ? "Активен" : "Ошибка: требуется вход"),
            trailing: conn.status == 'error' 
              ? ElevatedButton(
                  onPressed: () => conn.provider == 'google' ? auth.connectGoogle() : null, 
                  child: const Text("Обновить")
                )
              : const Icon(Icons.check_circle, color: Colors.green),
          ),
        )),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => auth.connectGoogle(),
                icon: const Icon(Icons.add),
                label: const Text("Google"),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => auth.connectOutlook(),
                icon: const Icon(Icons.add),
                label: const Text("Outlook"),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showComingSoon(String service) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$service интеграция скоро появится!")),
    );
  }

  Widget _buildMeetingsSection(MeetingProvider provider, LanguageProvider lang) {
    if (provider.isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
    }

    final pending = provider.meetings.where((m) => m.status == 'pending').toList();
    final confirmed = provider.meetings.where((m) => m.status == 'accepted').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pending.isNotEmpty) ...[
          Text(
            lang.translate('invites'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent),
          ),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pending.length,
            itemBuilder: (context, index) {
              final m = pending[index];
              return Card(
                color: Colors.blue.withOpacity(0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.blue.withOpacity(0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.mail_outline, color: Colors.blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                if (m.groupTitle != null) 
                                  Text("В группе: ${m.groupTitle}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text("${_formatDate(m.start)} ${_formatTime(m.start)}", style: const TextStyle(fontSize: 13)),
                          const Spacer(),
                          TextButton(
                            onPressed: () => provider.respondToInvite(m.inviteId!, 'declined'),
                            child: Text(lang.translate('decline'), style: const TextStyle(color: Colors.redAccent)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => provider.respondToInvite(m.inviteId!, 'accepted'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                            child: Text(lang.translate('accept')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
        ],

        Text(
          lang.translate('upcoming_meetings'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (confirmed.isEmpty)
          Card(
            color: Colors.grey.withOpacity(0.05),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Text(lang.translate('no_meetings'), style: const TextStyle(color: Colors.grey)),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: confirmed.take(5).length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final m = confirmed[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.event, color: Colors.white)),
                  title: Text(m.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("${_formatDate(m.start)} • ${_formatTime(m.start)}"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showMeetingDetails(context, m, lang),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildGroupSyncSection(GroupProvider groupProvider, AuthProvider authProvider, LanguageProvider lang) {
    if (groupProvider.chatId == null) {
      return Card(
        child: ExpansionTile(
          title: Text(lang.translate('connect_group'), style: const TextStyle(color: Colors.blue)),
          subtitle: Text(lang.translate('team_planning')),
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _groupController,
                    decoration: InputDecoration(
                      hintText: lang.translate('group_id_hint'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_groupController.text.isNotEmpty) groupProvider.setChatId(_groupController.text);
                      },
                      child: Text(lang.translate('connect_btn')),
                    ),
                  ),
                  if (groupProvider.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        groupProvider.error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text("ID: ${groupProvider.chatId}"),
            subtitle: Text("${lang.translate('participants_online')}: ${groupProvider.participants.length}"),
            trailing: IconButton(
              icon: const Icon(Icons.search, color: Colors.blue),
              onPressed: () => context.push('/scheduler'),
            ),
          ),
          if (groupProvider.participants.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Text(
                    lang.translate('bot_not_seeing_participants'),
                    style: const TextStyle(color: Colors.orange, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _launchURL("https://t.me/smartschedulertime_bot?startgroup=true"),
                    icon: const Icon(Icons.add_moderator),
                    label: Text(lang.translate('add_bot')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.withOpacity(0.1),
                      foregroundColor: Colors.blue,
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: SizedBox(
              height: 70,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: groupProvider.participants.length,
                itemBuilder: (context, index) {
                  final p = groupProvider.participants[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: Tooltip(
                      message: p.firstName ?? "User",
                      child: CircleAvatar(
                        radius: 25,
                        backgroundColor: p.isSynced ? Colors.green : Colors.grey,
                        child: CircleAvatar(
                          radius: 22,
                          backgroundImage: (p.photoUrl != null && p.photoUrl!.isNotEmpty) 
                              ? NetworkImage(p.photoUrl!) : null,
                          child: (p.photoUrl == null || p.photoUrl!.isEmpty) 
                              ? const Icon(Icons.person, size: 20) : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, AuthProvider auth, SyncProvider sync, GroupProvider group, LanguageProvider lang) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.access_time,
                title: lang.translate('work_hours'),
                description: lang.translate('setup_availability'),
                color: Colors.orange,
                onTap: () => context.push('/availability'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                icon: Icons.sync,
                title: lang.translate('sync'),
                description: sync.isSyncing ? lang.translate('syncing') : lang.translate('update_calendar'),
                color: Colors.blue,
                isLoading: sync.isSyncing,
                onTap: () => sync.sync(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _launchURL(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  String _formatDate(DateTime dt) {
    return "${dt.day}.${dt.month}.${dt.year}";
  }

  String _formatTime(DateTime dt) {
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  void _showMeetingDetails(BuildContext context, Meeting meeting, LanguageProvider lang) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(meeting.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    context.read<MeetingProvider>().deleteMeeting(meeting.id);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 18, color: Colors.blue),
                const SizedBox(width: 8),
                Text("${_formatDate(meeting.start)} с ${_formatTime(meeting.start)} до ${_formatTime(meeting.end)}"),
              ],
            ),
            if (meeting.location != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 18, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(meeting.location!),
                ],
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(lang.translate('close')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;
  final bool isLoading;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLoading)
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Text(description, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
