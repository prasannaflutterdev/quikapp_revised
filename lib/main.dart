import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'module/myapp.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

bool? hasInternet;

const bool pushNotify = bool.fromEnvironment('PUSH_NOTIFY', defaultValue: false);
const bool isCameraEnabled = bool.fromEnvironment('IS_CAMERA', defaultValue: false);
const bool isLocationEnabled = bool.fromEnvironment('IS_LOCATION', defaultValue: false);
const bool isMicEnabled = bool.fromEnvironment('IS_MIC', defaultValue: false);
const bool isNotificationEnabled = bool.fromEnvironment('IS_NOTIFICATION', defaultValue: false);
const bool isContactEnabled = bool.fromEnvironment('IS_CONTACT', defaultValue: false);
const bool isSMSEnabled = bool.fromEnvironment('IS_SMS', defaultValue: false);
const bool isPhoneEnabled = bool.fromEnvironment('IS_PHONE', defaultValue: false);
const bool isBluetoothEnabled = bool.fromEnvironment('IS_BLUETOOTH', defaultValue: false);
const splashTagline = String.fromEnvironment('SPLASH_TAGLINE');
const splashAnimation = String.fromEnvironment('SPLASH_ANIMATION');
const splashDuration = int.fromEnvironment('SPLASH_DURATION', defaultValue: 3);
const isSplashEnabled = bool.fromEnvironment('IS_SPLASH', defaultValue: false);

WebViewEnvironment? webViewEnvironment;

Future<FirebaseOptions> loadFirebaseOptionsFromJson() async {
  final jsonStr = await rootBundle.loadString('assets/google-services.json');
  final jsonMap = json.decode(jsonStr);

  final client = jsonMap['client'][0];
  return FirebaseOptions(
    apiKey: client['api_key'][0]['current_key'],
    appId: client['client_info']['mobilesdk_app_id'],
    messagingSenderId: jsonMap['project_info']['project_number'],
    projectId: jsonMap['project_info']['project_id'],
    storageBucket: jsonMap['project_info']['storage_bucket'],
  );
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("🔔 Background message: ${message.messageId}");
}
void main() async {
  const String webUrl = String.fromEnvironment('WEB_URL');
  WidgetsFlutterBinding.ensureInitialized();

  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
  InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      debugPrint("🔔 Notification tapped: ${response.payload}");
    },
  );

  debugPrint("Push Notify: $pushNotify \n WEBURL: $webUrl \n");

  if (pushNotify == true) {
    await Firebase.initializeApp(
      options: await loadFirebaseOptionsFromJson(),
    );

    FirebaseMessaging messaging = FirebaseMessaging.instance;
    messaging.getToken().then((token) {
      debugPrint("✅ FCM Token: $token");
    });

    await messaging.setAutoInitEnabled(true);
    await messaging.requestPermission();

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } else {
    debugPrint("🚫 Firebase not initialized (pushNotify: $pushNotify, isWeb: $kIsWeb)");
  }

  runApp(MyApp(webUrl: webUrl));
}
