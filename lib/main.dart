import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    await prefs.setString(_kEmail, email);
    await prefs.setString(_kPassHash, _hash(password));
    _email = email;
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
    ChangeNotifierProvider(
      create: (_) => AuthService(),
      child: const AccidentApp(),
    ),
  );
}

class AccidentApp extends StatelessWidget {
  const AccidentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Accident Alert',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const SplashGate(),
      routes: {
        LoginPage.route: (_) => const LoginPage(),
        RegisterPage.route: (_) => const RegisterPage(),
        HomePage.route: (_) => const HomePage(),
        LiveCamPage.route: (_) => const LiveCamPage(),
        SOSPage.route: (_) => const SOSPage(),
        SettingsPage.route: (_) => const SettingsPage(),
      },
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
// Main pages (stubs for now)
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
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, LiveCamPage.route),
                  icon: const Icon(Icons.videocam),
                  label: const Text('Live Cam (placeholder)'),
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

class LiveCamPage extends StatelessWidget {
  static const route = '/livecam';
  const LiveCamPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Camera')),
      body: const Center(child: Text('Camera + YOLO (TFLite) will go here')),
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
            const Text('If no response, app will send SMS + call (later).'),
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

class SettingsPage extends StatelessWidget {
  static const route = '/settings';
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(
        child: Text(
          'Contacts, thresholds, permissions will be configured here',
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// 5-second confirmation dialog (demo). Later: hook to GPS + SMS + Call.
// ──────────────────────────────────────────────────────────────────────────────
void showAccidentCountdown(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _CountdownDialog(
      onTimeout: () async {
        if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No response. Would send SMS + call.')),
        );
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
  int _seconds = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (_seconds == 0) {
        t.cancel();
        await widget.onTimeout();
      } else {
        setState(() => _seconds--);
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
      title: const Text('Possible Accident Detected'),
      content: Text('Are you safe? Sending alerts in $_seconds s...'),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Alert cancelled.')));
          },
          child: const Text("I'm Safe"),
        ),
      ],
    );
  }
}
