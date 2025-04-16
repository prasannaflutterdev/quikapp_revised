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

import '../main.dart';


class MainHome extends StatefulWidget {
  final String webUrl;
  const MainHome({super.key, required this.webUrl});

  @override
  State<MainHome> createState() => _MainHomeState();
}

class _MainHomeState extends State<MainHome> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;
  late PullToRefreshController? pullToRefreshController;

  String url = "";
  double progress = 0;
  final urlController = TextEditingController();
  DateTime? _lastBackPressed;
  String? _pendingInitialUrl; // 🔹 NEW

  InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: kDebugMode,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllow: "camera; microphone",
    iframeAllowFullscreen: true,
  );

  void requestPermissions() async {
    if (isCameraEnabled) await Permission.camera.request();
    if (isLocationEnabled) await Permission.location.request();
    if (isMicEnabled) await Permission.microphone.request();
    if (isNotificationEnabled) await Permission.notification.request();
    if (isContactEnabled) await Permission.contacts.request();
    if (isSMSEnabled) await Permission.sms.request();
    if (isPhoneEnabled) await Permission.phone.request();
    if (isBluetoothEnabled) await Permission.bluetooth.request();
    await Permission.storage.request();
  }

  @override
  void initState() {
    super.initState();
    requestPermissions();

    if (pushNotify == true) {
      setupFirebaseMessaging();
    }

    Connectivity().onConnectivityChanged.listen((_) {
      _checkInternetConnection();
    });

    _checkInternetConnection();

    pullToRefreshController = !kIsWeb &&
        [TargetPlatform.android, TargetPlatform.iOS].contains(defaultTargetPlatform)
        ? PullToRefreshController(
      settings: PullToRefreshSettings(color: Colors.blue),
      onRefresh: () async {
        if (defaultTargetPlatform == TargetPlatform.android) {
          webViewController?.reload();
        } else if (defaultTargetPlatform == TargetPlatform.iOS) {
          webViewController?.loadUrl(
            urlRequest: URLRequest(url: await webViewController?.getUrl()),
          );
        }
      },
    )
        : null;

    // ✅ Modified: Handle terminated state
    FirebaseMessaging.instance.getInitialMessage().then((message) async {
      if (message != null) {
        final internalUrl = message.data['url'];
        if (internalUrl != null && internalUrl.isNotEmpty) {
          _pendingInitialUrl = internalUrl; // 🔹 Save for later navigation
        }
        await _showLocalNotification(message);
      }
    });
  }

  /// ✅ Navigation from notification
  void _handleNotificationNavigation(RemoteMessage message) {
    final internalUrl = message.data['url'];
    if (internalUrl != null && webViewController != null) {
      webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri(internalUrl)),
      );
    } else {
      debugPrint('🔗 No URL to navigate');
    }
  }

  /// ✅ Setup push notification logic
  void setupFirebaseMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    if (Platform.isIOS) {
      await messaging.requestPermission(alert: true, badge: true, sound: true);
    }

    await messaging.subscribeToTopic('all_users');
    if (Platform.isAndroid) {
      await messaging.subscribeToTopic('android_users');
    } else if (Platform.isIOS) {
      await messaging.subscribeToTopic('ios_users');
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      await _showLocalNotification(message);
      _handleNotificationNavigation(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("📲 Opened from background tap: ${message.data}");
      _handleNotificationNavigation(message);
    });
  }

  /// ✅ Local push with optional image
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final android = notification?.android;
    final imageUrl = notification?.android?.imageUrl ?? message.data['image'];

    AndroidNotificationDetails androidDetails;

    AndroidNotificationDetails _defaultAndroidDetails() {
      return AndroidNotificationDetails(
        'default_channel',
        'Default',
        channelDescription: 'Default notification channel',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        icon: '@mipmap/ic_launcher',
      );
    }

    if (notification != null && android != null) {
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          final http.Response response = await http.get(Uri.parse(imageUrl));
          final tempDir = await getTemporaryDirectory();
          final filePath = '${tempDir.path}/notif_image.jpg';
          final file = File(filePath);
          await file.writeAsBytes(response.bodyBytes);

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
        } catch (e) {
          if (kDebugMode) {
            print('❌ Failed to load image: $e');
          }
          androidDetails = _defaultAndroidDetails();
        }
      } else {
        androidDetails = _defaultAndroidDetails();
      }

      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(android: androidDetails),
      );
    }
  }

  /// ✅ Connectivity
  Future<void> _checkInternetConnection() async {
    final result = await Connectivity().checkConnectivity();
    final isOnline = result != ConnectivityResult.none;
    if (mounted) {
      setState(() {
        hasInternet = isOnline;
      });
    }
  }

  /// ✅ Back button double-press exit
  Future<bool> _onBackPressed() async {
    DateTime now = DateTime.now();
    if (_lastBackPressed == null || now.difference(_lastBackPressed!) > Duration(seconds: 2)) {
      _lastBackPressed = now;
      Fluttertoast.showToast(
        msg: "Press back again to exit",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.black54,
        textColor: Colors.white,
      );
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
            child: Builder(
              builder: (context) {
                if (hasInternet == null) return const Center(child: CircularProgressIndicator());
                if (hasInternet == false) return const Center(child: Text('📴 No Internet Connection'));
                return InAppWebView(
                  key: webViewKey,
                  webViewEnvironment: webViewEnvironment,
                  initialUrlRequest: URLRequest(url: WebUri(widget.webUrl)),
                  pullToRefreshController: pullToRefreshController,
                  onWebViewCreated: (controller) {
                    webViewController = controller;
                    if (_pendingInitialUrl != null) {
                      webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(_pendingInitialUrl!)));
                      _pendingInitialUrl = null;
                    }
                  },
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
                );
              },
            ),
          ),
        ),
      ),
    );

  }
}