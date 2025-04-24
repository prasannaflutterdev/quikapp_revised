import 'package:flutter/material.dart';
// import '../main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Animations
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _rotationAnimation;

  final String splashUrl = const String.fromEnvironment('SPLASH');
  final String splashBgUrl = const String.fromEnvironment('SPLASH_BG');
  final String splashTagline = const String.fromEnvironment('SPLASH_TAGLINE');
  final String splashAnimation = const String.fromEnvironment('SPLASH_ANIMATION', defaultValue: 'zoom');
  final Color backgroundColor = _parseHexColor(const String.fromEnvironment('SPLASH_BG_COLOR', defaultValue: "#ffffff"));
  final Color taglineColor = _parseHexColor(const String.fromEnvironment('SPLASH_TAGLINE_COLOR', defaultValue: "#000000"));

  static Color _parseHexColor(String hexColor) {
    hexColor = hexColor.replaceFirst('#', '');
    if (hexColor.length == 6) hexColor = 'FF$hexColor';
    return Color(int.parse('0x$hexColor'));
  }

  @override
  void initState() {
    super.initState();
    debugPrint('📦 Splash image loaded from: $splashUrl');
    debugPrint('🎞️ Animation: $splashAnimation');

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();

    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildAnimatedLogo() {
    final image = Image.asset('assets/images/splash.png', width: 150, fit: BoxFit.fitWidth);

    switch (splashAnimation.toLowerCase()) {
      case 'fade':
        return FadeTransition(opacity: _fadeAnimation, child: image);
      case 'slide':
        return SlideTransition(position: _slideAnimation, child: image);
      case 'rotate':
        return RotationTransition(turns: _rotationAnimation, child: image);
      case 'none':
        return image;
      case 'zoom':
      default:
        return ScaleTransition(scale: _scaleAnimation, child: image);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          splashBgUrl.isNotEmpty
              ? Positioned.fill(
            child: Image.asset(
              'assets/images/splash_bg.png',
              fit: BoxFit.cover,
            ),
          )
              : const SizedBox.shrink(),
          Center(child: _buildAnimatedLogo()),
          if (splashTagline.isNotEmpty)
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Text(
                splashTagline,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: taglineColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}