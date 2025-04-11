import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseInitializer {
  static Future<void> initialize() async {
    const bool firebaseEnabled =
        bool.fromEnvironment('FIREBASE_ENABLED', defaultValue: false);

    if (firebaseEnabled && !kIsWeb) {
      try {
        await Firebase.initializeApp();
        debugPrint('✅ Firebase initialized.');
      } catch (e) {
        debugPrint('⚠️ Firebase initialization failed: $e');
      }
    } else {
      debugPrint('🚫 Firebase not enabled via PUSH_NOTIFY.');
    }
  }
}
