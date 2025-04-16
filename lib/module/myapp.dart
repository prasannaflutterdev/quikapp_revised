import 'package:flutter/material.dart';

import 'main_home.dart' show MainHome;
import 'splash_screen.dart';
import '../main.dart';

class MyApp extends StatefulWidget {

  final String webUrl;
  const MyApp({super.key, required this.webUrl});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool showSplash =isSplashEnabled;

  @override
  void initState() {
    super.initState();
    if (showSplash) {
      Future.delayed(Duration(seconds: splashDuration), () {
        setState(() {
          showSplash = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: showSplash
          ? SplashScreen()
          : MainHome(webUrl: widget.webUrl),
    );
  }
}