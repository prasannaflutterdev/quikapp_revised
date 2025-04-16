import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
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

  // final Color backgroundColor = _parseHexColor(const String.fromEnvironment('SPLASH_BG_COLOR', defaultValue: "#ffffff"));
  final Color taglineColor = _parseHexColor(const String.fromEnvironment('SPLASH_TAGLINE_COLOR', defaultValue: "#000000"));
  int _currentIndex = 0;
  static Color _parseHexColor(String hexColor) {
    hexColor = hexColor.replaceFirst('#', '');
    if (hexColor.length == 6) hexColor = 'FF$hexColor';
    return Color(int.parse('0x$hexColor'));
  }
  final bool isBottomMenu = const String.fromEnvironment('IS_BOTTOMMENU', defaultValue: 'false') == 'true';
  final String bottomMenuRaw = const String.fromEnvironment('BOTTOMMENU_ITEMS', defaultValue: '[]');
  final backgroundColor = const String.fromEnvironment('BOTTOMMENU_BG_COLOR', defaultValue: '#FFFFFF');
  final iconColor = const String.fromEnvironment('BOTTOMMENU_ICON_COLOR', defaultValue: '#000000');
  final textColor = const String.fromEnvironment('BOTTOMMENU_TEXT_COLOR', defaultValue: '#000000');
  final activeTabColor = const String.fromEnvironment('BOTTOMMENU_ACTIVE_TAB_COLOR', defaultValue: '#FF0000');
  final iconPosition = const String.fromEnvironment('BOTTOMMENU_ICON_POSITION', defaultValue: 'above');
  final visibleOn = const String.fromEnvironment('BOTTOMMENU_VISIBLE_ON', defaultValue: 'all');

// Convert the JSON string into a List of menu objects
  List<Map<String, dynamic>> bottomMenuItems = [];

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
    if (isLocationEnabled) await Permission.location.request(); // GPS
    if (isMicEnabled) await Permission.microphone.request();
    if (isContactEnabled) await Permission.contacts.request();
    if (isCalendarEnabled) await Permission.calendar.request();
    if (isNotificationEnabled) await Permission.notification.request();

    // Always request storage (as per your logic)
    await Permission.storage.request();
    if (isBiometricEnabled) {
      if (Platform.isIOS) {
        // Use raw value 33 for faceId (iOS)
        await Permission.byValue(33).request();
      } else if (Platform.isAndroid) {
        // No need to request biometric permission manually on Android
        // It's requested automatically by biometric plugins like local_auth
      }
    }
  }

  @override
  void initState() {
    super.initState();
    requestPermissions();

    if (pushNotify == true) {
      setupFirebaseMessaging();
    }
    if (isBottomMenu == true) {
    try {
      bottomMenuItems = List<Map<String, dynamic>>.from(json.decode(bottomMenuRaw));
    } catch (e) {
      if (kDebugMode) {
        print("Invalid bottom menu JSON: $e");
      }
    }
    }

    Connectivity().onConnectivityChanged.listen((_) {
      _checkInternetConnection();
    });

    _checkInternetConnection();

    if (!kIsWeb &&
        [TargetPlatform.android, TargetPlatform.iOS].contains(defaultTargetPlatform) &&
        isPullDown) {
      pullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(color: taglineColor),
          onRefresh: () async {
            try {
              if (defaultTargetPlatform == TargetPlatform.android) {
                await webViewController?.reload();
              } else if (defaultTargetPlatform == TargetPlatform.iOS) {
                final currentUrl = await webViewController?.getUrl();
                if (currentUrl != null) {
                  await webViewController?.loadUrl(
                    urlRequest: URLRequest(url: currentUrl),
                  );
                }
              }
            } catch (e) {
              debugPrint('❌ Refresh error: $e');
            } finally {
              pullToRefreshController?.endRefreshing(); // ✅ Important!
            }
          }
      );
    } else {
      pullToRefreshController = null;
    }

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

  IconData _getIconByName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return Icons.apps; // default icon when no name is provided
    }

    switch (name.toLowerCase()) {
      case 'home':
        return Icons.home;
      case 'info':
      case 'about':
        return Icons.info;
      case 'phone':
        return Icons.phone;
      case 'lock':
        return Icons.lock;
      case 'settings':
        return Icons.settings;
      case 'contact':
        return Icons.contact_page;
      case 'shop':
      case 'store':
        return Icons.storefront;
      case 'cart':
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'orders':
      case 'order':
        return Icons.receipt_long;
      case 'wishlist':
      case 'favorite':
      case 'like':
        return Icons.favorite;
      case 'category':
        return Icons.category;
      case 'account':
      case 'profile':
        return Icons.account_circle;
      case 'help':
        return Icons.help_outline;
      case 'notifications':
        return Icons.notifications;
      case 'search':
        return Icons.search;
      case 'offer':
      case 'discount':
        return Icons.local_offer;
      case 'services':
        return Icons.miscellaneous_services;
      case 'blogs':
      case 'blog':
        return Icons.article;
      case 'company':
      case 'about_us':
        return Icons.business;
      case 'more':
      case 'menu':
        return Icons.more_horiz;
      default:
        return Icons.apps;
    }
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

    AndroidNotificationDetails defaultAndroidDetails() {
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
          androidDetails = defaultAndroidDetails();
        }
      } else {
        androidDetails = defaultAndroidDetails();
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
          bottomNavigationBar: isBottomMenu
              ? BottomAppBar(
            color: _parseHexColor(backgroundColor),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(bottomMenuItems.length, (index) {
                final item = bottomMenuItems[index];
                final isActive = _currentIndex == index;

                final icon = Icon(
                  _getIconByName(item['icon']),
                  color: isActive
                      ? _parseHexColor(activeTabColor)
                      : _parseHexColor(iconColor),
                );

                final label = Text(
                  item['label'],
                  style: TextStyle(
                    fontSize: 12,
                    color: isActive
                        ? _parseHexColor(activeTabColor)
                        : _parseHexColor(textColor),
                  ),
                );

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _currentIndex = index;
                      webViewController?.loadUrl(
                        urlRequest: URLRequest(
                          url: WebUri(item['url']),
                        ),
                      );
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    child: iconPosition == 'beside'
                        ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [icon, const SizedBox(width: 6), label],
                    )
                        : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [icon, const SizedBox(height: 4), label],
                    ),
                  ),
                );
              }),
            ),
          )
              : null,


        ),

      ),
    );

  }
}