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

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

bool hasInternet = true;

const bool pushNotify = bool.fromEnvironment('PUSH_NOTIFY', defaultValue: false);
const bool isCameraEnabled = bool.fromEnvironment('IS_CAMERA', defaultValue: false);
const bool isLocationEnabled = bool.fromEnvironment('IS_LOCATION', defaultValue: false);
const bool isMicEnabled = bool.fromEnvironment('IS_MIC', defaultValue: false);
const bool isNotificationEnabled = bool.fromEnvironment('IS_NOTIFICATION', defaultValue: false);
const bool isContactEnabled = bool.fromEnvironment('IS_CONTACT', defaultValue: false);
const bool isSMSEnabled = bool.fromEnvironment('IS_SMS', defaultValue: false);
const bool isPhoneEnabled = bool.fromEnvironment('IS_PHONE', defaultValue: false);
const bool isBluetoothEnabled = bool.fromEnvironment('IS_BLUETOOTH', defaultValue: false);

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

  const initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: initSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      debugPrint("🔔 Notification tapped: ${response.payload}");
    },
  );

  if (pushNotify) {
    await Firebase.initializeApp(options: await loadFirebaseOptionsFromJson());

    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    await messaging.requestPermission();

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    messaging.getToken().then((token) {
      debugPrint("✅ FCM Token: $token");
    });
  }

  runApp(MyApp(webUrl: webUrl));
}

class MyApp extends StatefulWidget {
  final String webUrl;
  const MyApp({super.key, required this.webUrl});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;
  PullToRefreshController? pullToRefreshController;
  DateTime? _lastBackPressed;

  @override
  void initState() {
    super.initState();

    if (pushNotify) {
      FirebaseMessaging.instance.getToken().then((token) {
        debugPrint('✅ FCM Token: $token');
      });
      setupFirebaseMessaging();
    }

    requestPermissions();
    _checkInternetConnection();

    Connectivity().onConnectivityChanged.listen((_) {
      _checkInternetConnection();
    });

    if (!kIsWeb && [TargetPlatform.android, TargetPlatform.iOS].contains(defaultTargetPlatform)) {
      pullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(color: Colors.blue),
        onRefresh: () async {
          if (defaultTargetPlatform == TargetPlatform.android) {
            webViewController?.reload();
          } else {
            webViewController?.loadUrl(
              urlRequest: URLRequest(url: await webViewController?.getUrl()),
            );
          }
        },
      );
    }
  }

  void requestPermissions() async {
    if (isCameraEnabled) await Permission.camera.request();
    if (isLocationEnabled) await Permission.location.request();
    if (isMicEnabled) await Permission.microphone.request();
    if (isNotificationEnabled) await Permission.notification.request();
    if (isContactEnabled) await Permission.contacts.request();
    if (isSMSEnabled) await Permission.sms.request();
    if (isPhoneEnabled) await Permission.phone.request();
    if (isBluetoothEnabled) await Permission.bluetooth.request();
    await Permission.storage.request(); // Always request storage
  }

  void setupFirebaseMessaging() {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    if (Platform.isIOS) {
      messaging.requestPermission(alert: true, badge: true, sound: true);
    }

    messaging.subscribeToTopic('all_users');
    if (Platform.isAndroid) messaging.subscribeToTopic('android_users');
    if (Platform.isIOS) messaging.subscribeToTopic('ios_users');

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final notification = message.notification;
      final imageUrl = message.notification?.android?.imageUrl ?? message.data['image'];
      final internalUrl = message.data['url'];

      if (internalUrl != null && webViewController != null) {
        webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(internalUrl)));
      }

      if (notification != null) {
        AndroidNotificationDetails androidDetails;

        try {
          if (imageUrl != null && imageUrl.isNotEmpty) {
            final http.Response response = await http.get(Uri.parse(imageUrl));
            final filePath = '${(await getTemporaryDirectory()).path}/notif_image.jpg';
            await File(filePath).writeAsBytes(response.bodyBytes);

            androidDetails = AndroidNotificationDetails(
              'default_channel',
              'Default',
              channelDescription: 'Default notification channel',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              icon: '@mipmap/ic_launcher',
              styleInformation: BigPictureStyleInformation(
                FilePathAndroidBitmap(filePath),
                largeIcon: FilePathAndroidBitmap(filePath),
                contentTitle: '<b>${notification.title}</b>',
                summaryText: notification.body,
                htmlFormatContentTitle: true,
                htmlFormatSummaryText: true,
              ),
            );
          } else {
            androidDetails = AndroidNotificationDetails(
              'default_channel',
              'Default',
              channelDescription: 'Default notification channel',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
              icon: '@mipmap/ic_launcher',
            );
          }

          flutterLocalNotificationsPlugin.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(android: androidDetails),
          );
        } catch (e) {
          debugPrint('❌ Notification image error: $e');
        }
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      Fluttertoast.showToast(msg: "📲 Opened: ${message.notification?.title}");
    });
  }

  Future<void> _checkInternetConnection() async {
    final result = await Connectivity().checkConnectivity();
    setState(() {
      hasInternet = result != ConnectivityResult.none;
    });
  }

  Future<bool> _onBackPressed() async {
    final now = DateTime.now();
    if (_lastBackPressed == null || now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
      _lastBackPressed = now;
      Fluttertoast.showToast(msg: "Press back again to exit");
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WillPopScope(
        onWillPop: _onBackPressed,
        child: Scaffold(
          body: SafeArea(
            child: hasInternet
                ? InAppWebView(
              key: webViewKey,
              webViewEnvironment: webViewEnvironment,
              initialUrlRequest: URLRequest(url: WebUri(widget.webUrl)),
              pullToRefreshController: pullToRefreshController,
              onWebViewCreated: (controller) => webViewController = controller,
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final uri = navigationAction.request.url;
                if (uri != null && !uri.toString().contains(widget.webUrl)) {
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                    return NavigationActionPolicy.CANCEL;
                  }
                }
                return NavigationActionPolicy.ALLOW;
              },
            )
                : Center(child: Text('📴 No Internet Connection')),
          ),
        ),
      ),
    );
  }
}

// import 'dart:async';
// import 'dart:io';
// import 'package:http/http.dart' as http;
// import 'package:path_provider/path_provider.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// import 'package:fluttertoast/fluttertoast.dart';
// import 'package:url_launcher/url_launcher.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:connectivity_plus/connectivity_plus.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'dart:convert';
// import 'package:flutter/services.dart' show rootBundle;
// import 'package:permission_handler/permission_handler.dart';
//
// final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
//     FlutterLocalNotificationsPlugin();
//
// bool hasInternet = true;
//
// Future<FirebaseOptions> loadFirebaseOptionsFromJson() async {
//   final jsonStr = await rootBundle.loadString('assets/google-services.json');
//   final jsonMap = json.decode(jsonStr);
//
//   final client = jsonMap['client'][0];
//   final apiKey = client['api_key'][0]['current_key'];
//   final projectId = jsonMap['project_info']['project_id'];
//   final appId = client['client_info']['mobilesdk_app_id'];
//   final senderId = jsonMap['project_info']['project_number'];
//   final storageBucket = jsonMap['project_info']['storage_bucket'];
// debugPrint("Exported Json File:\n");
// debugPrint("apiKey: $apiKey\n");
// debugPrint("projectId: $projectId\n");
// debugPrint("appId: $appId\n");
// debugPrint("senderId: $senderId\n");
// debugPrint("storageBucket: $storageBucket\n");
//   return FirebaseOptions(
//     apiKey: apiKey,
//     appId: appId,
//     messagingSenderId: senderId,
//     projectId: projectId,
//     storageBucket: storageBucket,
//   );
// }
// const pushNotify = bool.fromEnvironment('PUSH_NOTIFY', defaultValue: false);
// const bool isCameraEnabled = bool.fromEnvironment('IS_CAMERA', defaultValue: false);
// const bool isLocationEnabled = bool.fromEnvironment('IS_LOCATION', defaultValue: false);
// const bool isMicEnabled = bool.fromEnvironment('IS_MIC', defaultValue: false);
// const bool isNotificationEnabled =
//     bool.fromEnvironment('IS_NOTIFICATION', defaultValue: false);
// const bool isContactEnabled = bool.fromEnvironment('IS_CONTACT', defaultValue: false);
// const bool isSMSEnabled = bool.fromEnvironment('IS_SMS', defaultValue: false);
// const bool isPhoneEnabled = bool.fromEnvironment('IS_PHONE', defaultValue: false);
// const bool isBluetoothEnabled =
//     bool.fromEnvironment('IS_BLUETOOTH', defaultValue: false);
//
// WebViewEnvironment? webViewEnvironment;
//
//
//
//
//
// void main() async {
//   const String webUrl = String.fromEnvironment('WEB_URL');
//   // const pushNotify = bool.fromEnvironment('PUSH_NOTIFY', defaultValue: false);
//   WidgetsFlutterBinding.ensureInitialized();
//     // Android settings for local notifications
//   const AndroidInitializationSettings initializationSettingsAndroid =
//       AndroidInitializationSettings('@mipmap/ic_launcher'); // your app icon
//
//   const InitializationSettings initializationSettings =
//       InitializationSettings(android: initializationSettingsAndroid);
//
//   // await flutterLocalNotificationsPlugin.initialize(initializationSettings);
//   await flutterLocalNotificationsPlugin.initialize(
//     initializationSettings,
//     onDidReceiveNotificationResponse: (NotificationResponse response) {
//       debugPrint("🔔 Notification tapped: ${response.payload}");
//       // Handle click action
//     },
//   );
//   debugPrint("Push Notify: $pushNotify \n WEBURL: $webUrl \n");
//   if (pushNotify == true) {
//   await Firebase.initializeApp(
//       options: await loadFirebaseOptionsFromJson(),
//     );
//     FirebaseMessaging messaging = FirebaseMessaging.instance;
//
//     messaging.getToken().then((token) {
//       debugPrint("✅ FCM Token: $token");
//     });
//
//     await messaging.setAutoInitEnabled(true);
//     await messaging.requestPermission();
//
//
//
//     FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
//
//     // await messaging.subscribeToTopic("all");
//   } else {
//     debugPrint(
//         "🚫 Firebase not initialized (pushNotify: $pushNotify, isWeb: $kIsWeb)");
//   }
//   debugPrint(
//       "Website URL: $webUrl");
//
//   runApp(MyApp(webUrl: webUrl));
// }
//
// Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
//   await Firebase.initializeApp();
//   debugPrint("🔔 Background message received: ${message.messageId}");
// }
//
// class MyApp extends StatefulWidget {
//   final String webUrl;
//   const MyApp({super.key, required this.webUrl});
//
//   @override
//   State<MyApp> createState() => _MyAppState();
// }
//
// class _MyAppState extends State<MyApp> {
//   final GlobalKey webViewKey = GlobalKey();
//   InAppWebViewController? webViewController;
//   late PullToRefreshController? pullToRefreshController;
//
//   String url = "";
//   double progress = 0;
//   final urlController = TextEditingController();
//   DateTime? _lastBackPressed;
//
//   InAppWebViewSettings settings = InAppWebViewSettings(
//     isInspectable: kDebugMode,
//     mediaPlaybackRequiresUserGesture: false,
//     allowsInlineMediaPlayback: true,
//     iframeAllow: "camera; microphone",
//     iframeAllowFullscreen: true,
//   );
//   void setupFirebaseMessaging() async {
//     FirebaseMessaging messaging = FirebaseMessaging.instance;
//
//     // Request permission on iOS
//     if (Platform.isIOS) {
//       await messaging.requestPermission(
//         alert: true,
//         badge: true,
//         sound: true,
//       );
//     }
//
//     // Subscribe to platform-specific topics
//     if (Platform.isAndroid) {
//       await messaging.subscribeToTopic('android_users');
//     } else if (Platform.isIOS) {
//       await messaging.subscribeToTopic('ios_users');
//     }
//
//     // Subscribe to general topic
//     await messaging.subscribeToTopic('all_users');
//
//     // Foreground message handler
// AndroidNotificationDetails _defaultAndroidDetails(
//         RemoteNotification notification) {
//       return AndroidNotificationDetails(
//         'default_channel',
//         'Default',
//         channelDescription: 'Default notification channel',
//         importance: Importance.max,
//         priority: Priority.high,
//         playSound: true,
//         icon: '@mipmap/ic_launcher',
//       );
//     }
//
//     FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
//       final internalUrl = message.data['url'];
//       final imageUrl =
//           message.notification?.android?.imageUrl ?? message.data['image'];
//       final notification = message.notification;
//       final android = notification?.android;
//
//            if (internalUrl != null && webViewController != null) {
//             webViewController?.loadUrl(
//               urlRequest: URLRequest(url: WebUri(internalUrl)),
//             );
//           }
//
//       if (notification != null && android != null) {
//         AndroidNotificationDetails androidDetails;
//
//         if (imageUrl != null && imageUrl.isNotEmpty) {
//           try {
//             final http.Response response = await http.get(Uri.parse(imageUrl));
//             final tempDir = await getTemporaryDirectory();
//             final filePath = '${tempDir.path}/notif_image.jpg';
//             final file = File(filePath);
//             await file.writeAsBytes(response.bodyBytes);
//
//               androidDetails = AndroidNotificationDetails(
//               'default_channel',
//               'Default',
//               channelDescription: 'Default notification channel',
//               importance: Importance.max,
//               priority: Priority.high,
//               playSound: true,
//               icon: '@mipmap/ic_launcher',
//               styleInformation: BigPictureStyleInformation(
//                 FilePathAndroidBitmap(filePath), // Big image
//                 largeIcon: FilePathAndroidBitmap(
//                     filePath), // Thumbnail/Avatar-style icon
//                 contentTitle: '<b>${notification.title}</b>', // Bold title
//                 summaryText: notification.body,
//                 htmlFormatContentTitle: true,
//                 htmlFormatSummaryText: true,
//               ),
//             );
//
//             // androidDetails = AndroidNotificationDetails(
//             //   'default_channel',
//             //   'Default',
//             //   channelDescription: 'Default notification channel',
//             //   importance: Importance.max,
//             //   priority: Priority.high,
//             //   styleInformation: BigPictureStyleInformation(
//             //     FilePathAndroidBitmap(filePath),
//             //     contentTitle: notification.title,
//             //     summaryText: notification.body,
//
//             //   ),
//             //   playSound: true,
//             //   icon: '@mipmap/ic_launcher',
//             // );
//           } catch (e) {
//             print('❌ Failed to load image: $e');
//             androidDetails = _defaultAndroidDetails(notification);
//           }
//         } else {
//           androidDetails = _defaultAndroidDetails(notification);
//         }
//
//         flutterLocalNotificationsPlugin.show(
//           notification.hashCode,
//           notification.title,
//           notification.body,
//           NotificationDetails(android: androidDetails),
//         );
//       }
//     });
//
//
//   // FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
//   //     final internalUrl = message.data['url'];
//   //     final imageUrl = message.notification?.android?.imageUrl ??
//   //         message.notification?.apple?.imageUrl ??
//   //         message.data['image'];
//
//   //     if (internalUrl != null && webViewController != null) {
//   //       webViewController?.loadUrl(
//   //         urlRequest: URLRequest(url: WebUri(internalUrl)),
//   //       );
//   //     }
//
//   //     final notification = message.notification;
//   //     final android = notification?.android;
//
//   //     if (notification != null && android != null) {
//   //       Fluttertoast.showToast(msg: "🔔 Notification: ${notification.title}");
//
//   //       AndroidNotificationDetails androidDetails;
//
//   //       if (imageUrl != null && imageUrl.isNotEmpty) {
//   //         // Download image to local temp file
//   //         final http.Response response = await http.get(Uri.parse(imageUrl));
//   //         final tempDir = await getTemporaryDirectory();
//   //         final filePath = '${tempDir.path}/notif_image.jpg';
//   //         final file = File(filePath);
//   //         await file.writeAsBytes(response.bodyBytes);
//
//   //         androidDetails = AndroidNotificationDetails(
//   //           'default_channel',
//   //           'Default',
//   //           channelDescription: 'Default notification channel',
//   //           importance: Importance.max,
//   //           priority: Priority.high,
//   //           playSound: true,
//   //           icon: '@mipmap/ic_launcher',
//   //           styleInformation: BigPictureStyleInformation(
//   //             FilePathAndroidBitmap(filePath),
//   //             contentTitle: notification.title,
//   //             summaryText: notification.body,
//   //           ),
//   //         );
//   //       } else {
//   //         androidDetails = AndroidNotificationDetails(
//   //           'default_channel',
//   //           'Default',
//   //           channelDescription: 'Default notification channel',
//   //           importance: Importance.max,
//   //           priority: Priority.high,
//   //           playSound: true,
//   //           icon: '@mipmap/ic_launcher',
//   //         );
//   //       }
//
//   //       flutterLocalNotificationsPlugin.show(
//   //         notification.hashCode,
//   //         notification.title,
//   //         notification.body,
//   //         NotificationDetails(android: androidDetails),
//   //       );
//   //     }
//   //   });
//
//      // FirebaseMessaging.onMessage.listen((RemoteMessage message) {
//     //     final internalUrl = message.data['url'];
//     //   if (internalUrl != null && webViewController != null) {
//     //     webViewController?.loadUrl(
//     //         urlRequest: URLRequest(url: WebUri(internalUrl)));
//     //   }
//     //   final notification = message.notification;
//     //   final android = notification?.android;
//
//     //   if (notification != null && android != null) {
//     //     Fluttertoast.showToast(msg: "🔔 Notification: ${notification.title}");
//
//     //     flutterLocalNotificationsPlugin.show(
//     //       notification.hashCode,
//     //       notification.title,
//     //       notification.body,
//     //       NotificationDetails(
//     //         android: AndroidNotificationDetails(
//     //           'default_channel',
//     //           'Default',
//     //           channelDescription: 'Default notification channel',
//     //           importance: Importance.max,
//     //           priority: Priority.high,
//     //           playSound: true,
//     //           icon: '@mipmap/ic_launcher',
//     //         ),
//     //       ),
//     //     );
//     //   }
//     // });
//
//     // Handle notification click when app is in background or terminated
//     FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
//       Fluttertoast.showToast(
//           msg: "📲 Opened from Notification: ${message.notification?.title}");
//       // Navigate or handle logic here
//     });
//   }
//
// void requestPermissions() async {
//     if (isCameraEnabled) await Permission.camera.request();
//     if (isLocationEnabled) await Permission.location.request();
//     if (isMicEnabled) await Permission.microphone.request();
//     if (isNotificationEnabled) await Permission.notification.request();
//     if (isContactEnabled) await Permission.contacts.request();
//     if (isSMSEnabled) await Permission.sms.request();
//     if (isPhoneEnabled) await Permission.phone.request();
//     if (isBluetoothEnabled) await Permission.bluetooth.request();
//
//     // Always-requested
//     await Permission.storage.request(); // For Android
//   }
//
//   @override
//   void initState() {
//     super.initState();
//
//     if (pushNotify == true) {
//       FirebaseMessaging.instance.getToken().then((token) {
//         debugPrint('✅ FCM Token: $token');
//       });
//
//       setupFirebaseMessaging();
//       // FirebaseMessaging.instance.subscribeToTopic("all");
//       // FirebaseMessaging.instance.requestPermission();
//       // FirebaseMessaging.onMessage.listen((RemoteMessage message) {
//       //   Fluttertoast.showToast(
//       //       msg: "🔔 Notification: ${message.notification?.title}");
//       //       final notification = message.notification;
//       //   final android = message.notification?.android;
//
//       //   if (notification != null && android != null) {
//       //     Fluttertoast.showToast(
//       //         msg: "🔔 Notification: ${message.notification?.title}");
//       //     flutterLocalNotificationsPlugin.show(
//       //       notification.hashCode,
//       //       notification.title,
//       //       notification.body,
//       //       NotificationDetails(
//       //         android: AndroidNotificationDetails(
//       //           'default_channel', // channel ID
//       //           'Default', // channel name
//       //           channelDescription: 'Default notification channel',
//       //           importance: Importance.max,
//       //           priority: Priority.high,
//       //           playSound: true,
//       //           icon: '@mipmap/ic_launcher',
//       //         ),
//       //       ),
//       //     );
//       //   }
//       // });
//     }
//
//     Connectivity().onConnectivityChanged.listen((_) {
//       _checkInternetConnection();
//     });
//
//     _checkInternetConnection();
//
//     // Enable pull-to-refresh for mobile platforms
//     pullToRefreshController = !kIsWeb &&
//             [TargetPlatform.android, TargetPlatform.iOS]
//                 .contains(defaultTargetPlatform)
//         ? PullToRefreshController(
//             settings: PullToRefreshSettings(color: Colors.blue),
//             onRefresh: () async {
//               if (defaultTargetPlatform == TargetPlatform.android) {
//                 webViewController?.reload();
//               } else if (defaultTargetPlatform == TargetPlatform.iOS) {
//                 webViewController?.loadUrl(
//                   urlRequest:
//                       URLRequest(url: await webViewController?.getUrl()),
//                 );
//               }
//             },
//           )
//         : null;
//   }
//
//   Future<void> _checkInternetConnection() async {
//     final result = await Connectivity().checkConnectivity();
//     final isOnline = result != ConnectivityResult.none;
//
//     if (mounted) {
//       setState(() {
//         hasInternet = isOnline;
//       });
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       home: WillPopScope(
//         onWillPop: _onBackPressed,
//         child: Scaffold(
//           body: SafeArea(
//             child: hasInternet
//                 ? InAppWebView(
//                     key: webViewKey,
//                     webViewEnvironment: webViewEnvironment,
//                     initialUrlRequest: URLRequest(url: WebUri(widget.webUrl)),
//                     // settings: settings,
//                     pullToRefreshController: pullToRefreshController,
//                     onWebViewCreated: (controller) {
//                       webViewController = controller;
//                     },
//                     shouldOverrideUrlLoading:
//                         (controller, navigationAction) async {
//                       var uri = navigationAction.request.url;
//
//                       if (uri != null &&
//                           !uri.toString().contains(widget.webUrl)) {
//                         if (await canLaunchUrl(uri)) {
//                           await launchUrl(uri,
//                               mode: LaunchMode.externalApplication);
//                         }
//                         return NavigationActionPolicy.CANCEL;
//                       }
//                       return NavigationActionPolicy.ALLOW;
//                     },
//                   )
//                 : noInternetScreen(),
//           ),
//         ),
//       ),
//     );
//   }
//
//   Future<bool> _onBackPressed() async {
//     DateTime now = DateTime.now();
//     if (_lastBackPressed == null ||
//         now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
//       _lastBackPressed = now;
//       Fluttertoast.showToast(
//         msg: "Press back again to exit",
//         toastLength: Toast.LENGTH_SHORT,
//         gravity: ToastGravity.BOTTOM,
//         backgroundColor: Colors.black54,
//         textColor: Colors.white,
//       );
//       return Future.value(false);
//     }
//     return Future.value(true);
//   }
//
//   Widget noInternetScreen() {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(24.0),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             const Icon(Icons.wifi_off, size: 100, color: Colors.grey),
//             const SizedBox(height: 20),
//             const Text(
//               'No Internet Connection',
//               style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
//             ),
//             const SizedBox(height: 10),
//             Text(
//               'Please check your network settings and try again.',
//               textAlign: TextAlign.center,
//               style: TextStyle(fontSize: 16, color: Colors.grey[600]),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
//
