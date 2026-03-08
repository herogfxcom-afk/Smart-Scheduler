import '../../models/busy_slot.dart';

/// Simple in-memory cache of busy slots (IDs to lists of slots).
/// Replaces Isar local DB, which is incompatible with Flutter Web.
class DatabaseService {
  final Map<int, List<BusySlot>> _cache = {};

  Future<void> saveBusySlots(List<BusySlot> slots) async {
    _cache[-1] = slots; // store under a shared key
  }

  Future<List<BusySlot>> getBusySlots() async {
    return List.unmodifiable(_cache[-1] ?? []);
  }

  void clear() {
    _cache.clear();
  }
}
