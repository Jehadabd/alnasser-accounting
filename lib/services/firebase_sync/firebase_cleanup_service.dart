import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_sync_config.dart';

class FirebaseCleanupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _lastCleanupKey = 'last_firebase_cleanup_time';
  static const int _cleanupIntervalHours = 24; // Run once a day

  Future<void> runDailyCleanup() async {
    try {
      final isEnabled = await FirebaseSyncSecuritySettings.isAutoCleanupEnabled();
      if (!isEnabled) {
        return; // التنظيف التلقائي معطل من الإعدادات
      }

      final prefs = await SharedPreferences.getInstance();
      final lastCleanupStr = prefs.getString(_lastCleanupKey);
      
      if (lastCleanupStr != null) {
        final lastCleanup = DateTime.parse(lastCleanupStr);
        final difference = DateTime.now().difference(lastCleanup).inHours;
        
        if (difference < _cleanupIntervalHours) {
          // Cleanup was already run recently, skip.
          return;
        }
      }

      print('🧹 FirebaseCleanupService: Starting cleanup of old data...');
      
      final daysToKeep = await FirebaseSyncSecuritySettings.getAutoDeleteDays();
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
      final cutoffTimestamp = Timestamp.fromDate(cutoffDate);

      // Clean up Invoices
      await _deleteOldDocuments('invoices', cutoffTimestamp);
      
      // Clean up Transactions
      await _deleteOldDocuments('transactions', cutoffTimestamp);

      // Clean up Debt Transactions
      await _deleteOldDocuments('debt_transactions', cutoffTimestamp);

      // Save the cleanup time
      await prefs.setString(_lastCleanupKey, DateTime.now().toIso8601String());
      print('✅ FirebaseCleanupService: Cleanup completed successfully.');
      
    } catch (e) {
      print('❌ FirebaseCleanupService - Error running cleanup: $e');
    }
  }

  Future<void> _deleteOldDocuments(String collectionName, Timestamp cutoffTimestamp) async {
    try {
      // Query documents where uploaded_at is older than the cutoff date
      final querySnapshot = await _firestore
          .collection(collectionName)
          .where('uploaded_at', isLessThan: cutoffTimestamp)
          .limit(500) // Process in batches to avoid memory/timeout issues
          .get();

      if (querySnapshot.docs.isEmpty) {
        return;
      }

      print('🗑️ FirebaseCleanupService: Found ${querySnapshot.docs.length} old documents in $collectionName. Deleting...');

      // Use a WriteBatch for efficient deletion
      WriteBatch batch = _firestore.batch();
      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      // If we hit the limit, there might be more. Run recursively until empty.
      if (querySnapshot.docs.length == 500) {
        await _deleteOldDocuments(collectionName, cutoffTimestamp);
      }
    } catch (e) {
      print('❌ FirebaseCleanupService - Error deleting from $collectionName: $e');
    }
  }
}
