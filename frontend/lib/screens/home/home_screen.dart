import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/group_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
                const Text(
                  "📊 Magic Sync",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: groupProvider.participants.length,
                    itemBuilder: (context, index) {
                      final p = groupProvider.participants[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
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
                                radius: 25,
                                backgroundImage: p.photoUrl != null ? NetworkImage(p.photoUrl!) : null,
                                child: p.photoUrl == null ? const Icon(Icons.person) : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              p.firstName ?? "User",
                              style: TextStyle(
                                fontSize: 12,
                                color: p.isSynced ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const Divider(),
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
                    context.push('/scheduler');
                  },
                  icon: const Icon(Icons.search),
                  label: const Text("Find Best Time Slots"),
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
