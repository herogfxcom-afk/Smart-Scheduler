import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/group_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _groupController = TextEditingController();

  @override
  void dispose() {
    _groupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final syncProvider = context.watch<SyncProvider>();
    final user = authProvider.user;
    final groupProvider = context.watch<GroupProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(groupProvider.chatId != null ? "Group Sync (${groupProvider.chatId})" : "Smart Scheduler"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              authProvider.init();
              groupProvider.syncWithGroup();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => authProvider.logout(),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Group Sync Section (Magic Sync)
              if (groupProvider.chatId != null) ...[
                Text(
                  "📊 Syncing with Group",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                ),
                if (groupProvider.error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(groupProvider.error!, style: const TextStyle(color: Colors.red, fontSize: 12), textAlign: TextAlign.center),
                  ),
                if (groupProvider.isLoading)
                  const CircularProgressIndicator()
                else if (groupProvider.participants.isEmpty)
                  const Text("Нет участников. Поделитесь ботом в группе или обновите.", style: TextStyle(color: Colors.grey))
                else
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: groupProvider.participants.length,
                      itemBuilder: (context, index) {
                        final p = groupProvider.participants[index];
                        final isMe = p.telegramId == authProvider.user?.telegramId;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: p.isSynced ? Colors.green : Colors.grey.withOpacity(0.5),
                                    width: 3,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 30,
                                  backgroundImage: (p.photoUrl != null && p.photoUrl!.isNotEmpty) 
                                      ? NetworkImage(p.photoUrl!) : null,
                                  child: (p.photoUrl == null || p.photoUrl!.isEmpty) 
                                      ? const Icon(Icons.person, size: 30) : null,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isMe ? "You" : (p.firstName ?? "User"),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                                  color: p.isSynced ? Colors.green : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                if (groupProvider.participants.length == 1)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text("Остальные участники скоро появятся...", style: TextStyle(fontSize: 11, color: Colors.orange)),
                  ),
                const Divider(),
              ] else ...[
                 // Manual Group Join
                 ExpansionTile(
                   initiallyExpanded: false,
                   title: const Text("Подключить группу вручную", style: TextStyle(fontSize: 14, color: Colors.blue)),
                   subtitle: const Text("Вставьте ID группы или ссылку-приглашение", style: TextStyle(fontSize: 11)),
                   children: [
                     Padding(
                       padding: const EdgeInsets.all(16.0),
                       child: Column(
                         children: [
                           TextField(
                             controller: _groupController,
                             decoration: InputDecoration(
                               hintText: "Например, -10012345 или t.me/join...",
                               hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                               border: const OutlineInputBorder(),
                               suffixIcon: IconButton(
                                 icon: const Icon(Icons.clear, color: Colors.grey),
                                 onPressed: () {
                                   _groupController.clear();
                                 },
                               )
                             ),
                             onSubmitted: (val) {
                               if (val.trim().isNotEmpty) groupProvider.setChatId(val.trim());
                             },
                           ),
                           const SizedBox(height: 12),
                           SizedBox(
                             width: double.infinity,
                             child: ElevatedButton(
                               style: ElevatedButton.styleFrom(
                                 backgroundColor: Colors.blue,
                                 foregroundColor: Colors.white,
                               ),
                               onPressed: () {
                                 final val = _groupController.text.trim();
                                 if (val.isNotEmpty) {
                                   groupProvider.setChatId(val);
                                   FocusScope.of(context).unfocus();
                                 }
                               },
                               child: const Text("Синхронизировать"),
                             ),
                           ),
                         ],
                       ),
                     )
                   ],
                 )
              ],

              const SizedBox(height: 24),
              Text(
                "Welcome, ${user?.firstName ?? 'User'}!",
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              
              // Calendar Status Chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    avatar: Icon(Icons.check_circle, color: authProvider.isConnected ? Colors.green : Colors.grey),
                    label: const Text("Google"),
                  ),
                  Chip(
                    avatar: Icon(Icons.check_circle, color: authProvider.isAppleConnected ? Colors.green : Colors.grey),
                    label: const Text("Apple"),
                  ),
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Sync Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Calendar Sync", style: TextStyle(fontWeight: FontWeight.bold)),
                          if (syncProvider.isSyncing)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            const Icon(Icons.sync, color: Colors.blue),
                        ],
                      ),
                      const Divider(),
                      if (syncProvider.lastSyncTime != null)
                        Column(
                          children: [
                            Text("Last synced: ${syncProvider.lastSyncTime.toString().split('.')[0]}"),
                            Text("Events found: ${syncProvider.syncedCount}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        )
                      else
                        const Text("Never synced"),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: syncProvider.isSyncing ? null : () => syncProvider.sync(),
                        child: const Text("Sync Now"),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (groupProvider.chatId == null) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text("Сначала подключитесь к группе (поле выше)"))
                       );
                    } else {
                       context.push('/scheduler');
                    }
                  },
                  icon: const Icon(Icons.search),
                  label: const Text("Найти свободное время (Team)"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
