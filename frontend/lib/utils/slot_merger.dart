import '../models/time_slot.dart';

class SlotMerger {
  /// Merges overlapping or perfectly adjacent slots of the same type/source.
  static List<TimeSlot> merge(List<TimeSlot> slots) {
    if (slots.isEmpty) return [];

    // Sort by start time
    final sorted = List<TimeSlot>.from(slots)..sort((a, b) => a.start.compareTo(b.start));
    
    final List<TimeSlot> merged = [];
    if (sorted.isEmpty) return [];

    TimeSlot current = sorted.first;

    for (int i = 1; i < sorted.length; i++) {
      final next = sorted[i];

      // If they overlap OR are exactly adjacent AND have the same properties
      bool canMerge = next.start.isBefore(current.end) || next.start.isAtSameMomentAs(current.end);
      bool sameProperties = next.type == current.type && 
                           next.availability == current.availability &&
                           next.sourceUserId == current.sourceUserId;

      if (canMerge && sameProperties) {
        // Merge them by extending the end time
        final newEnd = next.end.isAfter(current.end) ? next.end : current.end;
        current = TimeSlot(
          start: current.start,
          end: newEnd,
          type: current.type,
          availability: current.availability,
          freeCount: current.freeCount,
          totalCount: current.totalCount,
          sourceUserId: current.sourceUserId,
        );
      } else {
        merged.add(current);
        current = next;
      }
    }
    
    merged.add(current);
    return merged;
  }
}
