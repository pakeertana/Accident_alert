import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pages/sensors_page.dart'; // <- our sensors page

// ──────────────────────────────────────────────────────────────────────────────
// Simple offline Auth (demo). We'll swap to secure storage later.
// ──────────────────────────────────────────────────────────────────────────────
class AuthService extends ChangeNotifier {
  bool _ready = false;
  String? _email;

  bool get ready => _ready;
  bool get isLoggedIn => _email != null;
  String? get email => _email;

  static const _kEmail = 'user_email';
  static const _kPassHash = 'user_hash';

  AuthService() {
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _email = prefs.getString(_kEmail);
    _ready = true;
    notifyListeners();
  }

  String _hash(String s) => sha256.convert(utf8.encode(s)).toString();

  Future<String?> register(String email, String password) async {
    if (email.isEmpty || password.length < 6) {
      return 'Email required and password must be 6+ chars';
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEmail, email.trim());
    await prefs.setString(_kPassHash, _hash(password));
    _email = email.trim();
    notifyListeners();
    return null;
  }

  Future<String?> signIn(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final e = prefs.getString(_kEmail);
    final h = prefs.getString(_kPassHash);
    if (e == null || h == null) return 'No user registered. Please register.';
    if (email.trim() != e || _hash(password) != h) return 'Invalid credentials';
    _email = e;
    notifyListeners();
    return null;
  }

  Future<void> signOut() async {
    _email = null;
    notifyListeners();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(create: (_) => AuthService(), child: const MyApp()),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Accident Alert',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const MainNavigation(),
      routes: {
        LoginPage.route: (_) => const LoginPage(),
        RegisterPage.route: (_) => const RegisterPage(),
        HomePage.route: (_) => const HomePage(),
        LiveCamPage.route: (_) => const LiveCamPage(),
        SOSPage.route: (_) => const SOSPage(),
        SettingsPage.route: (_) => const SettingsPage(),
        SensorsPage.route: (_) => const SensorsPage(),
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const LoginPage(),
    const RegisterPage(),
    const SensorsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.login), label: "Login"),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_add),
            label: "Register",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.sensors), label: "Sensors"),
        ],
      ),
    );
  }
}

// Wait for AuthService then route to login/home
class SplashGate extends StatelessWidget {
  const SplashGate({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (_, auth, __) {
        if (!auth.ready) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return auth.isLoggedIn ? const HomePage() : const LoginPage();
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Login / Register (offline demo)
// ──────────────────────────────────────────────────────────────────────────────
class LoginPage extends StatefulWidget {
  static const route = '/login';
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (v) =>
                        (v == null || v.length < 6) ? '6+ chars' : null,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading
                          ? null
                          : () async {
                              if (!_form.currentState!.validate()) return;
                              setState(() => _loading = true);
                              final err = await context
                                  .read<AuthService>()
                                  .signIn(_email.text.trim(), _pass.text);
                              setState(() => _loading = false);
                              if (!mounted) return;
                              if (err != null) {
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(SnackBar(content: Text(err)));
                              } else {
                                Navigator.pushReplacementNamed(
                                  context,
                                  HomePage.route,
                                );
                              }
                            },
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign In'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, RegisterPage.route),
                    child: const Text('Create an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterPage extends StatefulWidget {
  static const route = '/register';
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pass,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (v) =>
                        (v == null || v.length < 6) ? '6+ chars' : null,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading
                          ? null
                          : () async {
                              if (!_form.currentState!.validate()) return;
                              setState(() => _loading = true);
                              final err = await context
                                  .read<AuthService>()
                                  .register(_email.text.trim(), _pass.text);
                              setState(() => _loading = false);
                              if (!mounted) return;
                              if (err != null) {
                                ScaffoldMessenger.of(
                                  context,
                                ).showSnackBar(SnackBar(content: Text(err)));
                              } else {
                                Navigator.pushReplacementNamed(
                                  context,
                                  HomePage.route,
                                );
                              }
                            },
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create Account'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Main pages
// ──────────────────────────────────────────────────────────────────────────────
class HomePage extends StatelessWidget {
  static const route = '/home';
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accident Detection'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, SettingsPage.route),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await context.read<AuthService>().signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, LoginPage.route);
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Hello ${auth.email ?? ''}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: 260,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, SensorsPage.route),
                  icon: const Icon(Icons.sensors),
                  label: const Text('Sensors Page'),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: 260,
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, LiveCamPage.route),
                  icon: const Icon(Icons.videocam),
                  label: const Text('Live Camera'),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: 260,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, SOSPage.route),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('SOS Page'),
                ),
              ),

              const SizedBox(height: 24),
              TextButton(
                onPressed: () => showAccidentCountdown(context),
                child: const Text('Demo: Trigger 5s Countdown'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LiveCamPage extends StatefulWidget {
  static const route = '/livecam';
  const LiveCamPage({super.key});

  @override
  State<LiveCamPage> createState() => _LiveCamPageState();
}

class _LiveCamPageState extends State<LiveCamPage> {
  CameraController? _controller;
  String _status = 'Requesting camera permission...';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (kIsWeb) {
      setState(
        () => _status = 'Camera preview is not supported in this demo on Web.',
      );
      return;
    }

    try {
      final perm = await Permission.camera.request();
      if (!perm.isGranted) {
        setState(() => _status = 'Camera permission denied');
        return;
      }

      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _status = 'No cameras found');
        return;
      }

      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );

      final ctrl = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {
        _controller = ctrl;
        _status = 'Preview ready';
      });
    } catch (e) {
      setState(() => _status = 'Camera init error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller?.value.isInitialized == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Live Camera')),
      body: Center(
        child: ready
            ? AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: CameraPreview(_controller!),
              )
            : Text(_status),
      ),
    );
  }
}

class SOSPage extends StatelessWidget {
  static const route = '/sos';
  const SOSPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SOS')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'If no response, the app will prepare SMS (and optional call).',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => showAccidentCountdown(context),
              child: const Text('Test 5s Countdown'),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  static const route = '/settings';
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _contactCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _contactCtrl.text = prefs.getString('primary_contact') ?? '112';
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('primary_contact', _contactCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  @override
  void dispose() {
    _contactCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _contactCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Emergency Contact Number',
                hintText: '+91XXXXXXXXXX or 112',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _save, child: const Text('Save')),
            ),
            const SizedBox(height: 24),
            const Text('Thresholds & other settings can be added here later.'),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// 5-second confirmation dialog + SOS helpers
// ──────────────────────────────────────────────────────────────────────────────
void showAccidentCountdown(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CountdownDialog(
      onTimeout: () async {
        // Close dialog
        if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        // Try to prepare SMS with location
        await sendAccidentAlert(context);
      },
    ),
  );
}

class _CountdownDialog extends StatefulWidget {
  final FutureOr<void> Function() onTimeout;
  const _CountdownDialog({required this.onTimeout});

  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog> {
  int _secondsLeft = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (_secondsLeft == 0) {
        t.cancel();
        await widget.onTimeout();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Possible Accident Detected 🚨"),
      content: Text(
        "Sending SOS in $_secondsLeft seconds.\nTap CANCEL if you're safe.",
      ),
      actions: [
        TextButton(
          onPressed: () {
            _timer?.cancel();
            Navigator.of(context).pop();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Alert cancelled.')));
          },
          child: const Text("CANCEL"),
        ),
      ],
    );
  }
}

// SOS helpers
Future<String> _getPrimaryContact() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('primary_contact')?.trim();
  if (saved != null && saved.isNotEmpty) return saved;
  return '112';
}

Future<Position?> _getPosition(BuildContext context) async {
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location services disabled.')),
      );
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission denied.')),
      );
      return null;
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  } catch (_) {
    return null;
  }
}

String _buildSmsBody(Position? p) {
  final base = 'Accident detected. I need help.';
  if (p == null) return base;
  final link = 'https://maps.google.com/?q=${p.latitude},${p.longitude}';
  return '$base Location: $link';
}

Future<void> _launchSms(String to, String body) async {
  final uri = Uri.parse('sms:$to?body=${Uri.encodeComponent(body)}');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    throw 'Cannot open SMS app';
  }
}

Future<void> sendAccidentAlert(BuildContext context) async {
  try {
    final contact = await _getPrimaryContact();
    final pos = await _getPosition(context);
    final body = _buildSmsBody(pos);

    await _launchSms(contact, body);

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('SOS prepared for $contact')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Failed to send alert: $e')));
  }
}
