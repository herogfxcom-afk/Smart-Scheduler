import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/availability_provider.dart';
import '../../models/meeting.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _groupController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MeetingProvider>().fetchMyMeetings();
    });
  }

  @override
  void dispose() {
    _groupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final groupProvider = context.watch<GroupProvider>();
    final meetingProvider = context.watch<MeetingProvider>();
    final user = authProvider.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Magic Sync Dashboard"),
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
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/availability'),
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
                         "Привет, ${user?.firstName ?? 'Пользователь'}!",
                         style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                       ),
                       Text(
                         user?.username != null ? "@${user!.username}" : "Настройте ваш профиль",
                         style: const TextStyle(color: Colors.grey),
                       ),
                     ],
                   ),
                ],
              ),
              const SizedBox(height: 24),

              // Upcoming Meetings Section
              const Text(
                "Ближайшие встречи",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildMeetingsSection(meetingProvider),
              
              const SizedBox(height: 32),

              // Active Sync Section
              const Text(
                "Групповая синхронизация",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildGroupSyncSection(groupProvider, authProvider),

              const SizedBox(height: 32),

              // My Calendars Section
              const Text(
                "Подключенные календари",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildCalendarsSection(authProvider),
              
              const SizedBox(height: 32),

              // Quick Actions / Services
              const Text(
                "Сервисы и настройки",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildQuickActions(context, authProvider, syncProvider, groupProvider),
              
              const SizedBox(height: 24),
            ],
          ),
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
              conn.provider == 'google' ? Icons.mail : Icons.apple,
              color: conn.provider == 'google' ? Colors.red : Colors.grey,
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
                onPressed: () => _showComingSoon("Outlook"),
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

  Widget _buildMeetingsSection(MeetingProvider provider) {
    if (provider.isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
    }
    if (provider.meetings.isEmpty) {
      return Card(
        color: Colors.grey.withOpacity(0.05),
        child: const Padding(
          padding: EdgeInsets.all(24.0),
          child: Center(
            child: Text("Запланированных встреч нет", style: TextStyle(color: Colors.grey)),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: provider.meetings.take(3).length, // Show top 3
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final m = provider.meetings[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.event, color: Colors.white)),
            title: Text(m.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${_formatDate(m.start)} • ${_formatTime(m.start)}"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showMeetingDetails(context, m),
          ),
        );
      },
    );
  }

  Widget _buildGroupSyncSection(GroupProvider groupProvider, AuthProvider authProvider) {
    if (groupProvider.chatId == null) {
      return Card(
        child: ExpansionTile(
          title: const Text("Подключить группу", style: TextStyle(color: Colors.blue)),
          subtitle: const Text("Для командного планирования"),
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _groupController,
                    decoration: const InputDecoration(
                      hintText: "ID группы или ссылка",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_groupController.text.isNotEmpty) groupProvider.setChatId(_groupController.text);
                      },
                      child: const Text("Подключить"),
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
            title: Text("Группа: ${groupProvider.chatId}"),
            subtitle: Text("Участников онлайн: ${groupProvider.participants.length}"),
            trailing: IconButton(
              icon: const Icon(Icons.search, color: Colors.blue),
              onPressed: () => context.push('/scheduler'),
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

  Widget _buildQuickActions(BuildContext context, AuthProvider auth, SyncProvider sync, GroupProvider group) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ActionCard(
                icon: Icons.access_time,
                title: "Рабочие часы",
                description: "Настройте доступность",
                color: Colors.orange,
                onTap: () => context.push('/availability'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionCard(
                icon: Icons.sync,
                title: "Синхронизация",
                description: sync.isSyncing ? "В процессе..." : "Обновить календарь",
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

  String _formatDate(DateTime dt) {
    return "${dt.day}.${dt.month}.${dt.year}";
  }

  String _formatTime(DateTime dt) {
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  void _showMeetingDetails(BuildContext context, Meeting meeting) {
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
                child: const Text("Закрыть"),
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
