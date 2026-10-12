import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'device.dart';
import 'store.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (WalkingDevice.sandboxEnabled) {
    throw StateError(
      'Build Langkah Sandbox with the lib/sandbox.dart entry point.',
    );
  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  const url = String.fromEnvironment('SUPABASE_URL'),
      key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  SupabaseClient? client;
  String? error;
  if (url.isNotEmpty && key.isNotEmpty) {
    try {
      await Supabase.initialize(url: url, publishableKey: key);
      client = Supabase.instance.client;
    } catch (_) {
      error = 'Could not connect. Check your connection and restart Langkah.';
    }
  }
  runApp(
    LangkahApp(
      store: LangkahStore(client: client),
      startupError: error,
    ),
  );
}

class LangkahApp extends StatelessWidget {
  final LangkahStore store;
  final String? startupError;
  const LangkahApp({super.key, required this.store, this.startupError});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Langkah',
    debugShowCheckedModeBanner: false,
    theme: langkahTheme(),
    home: AppRoot(store: store, startupError: startupError),
  );
}

class AppRoot extends StatefulWidget {
  final LangkahStore store;
  final String? startupError;
  const AppRoot({super.key, required this.store, this.startupError});
  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  int tab = 0;
  String? workspaceRole;
  StreamSubscription<AuthState>? auth;
  LangkahStore get s => widget.store;
  @override
  void initState() {
    super.initState();
    s.addListener(changed);
    auth = s.client?.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.passwordRecovery && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RecoveryPage(store: s, recovering: true),
          ),
        );
      }
      if (event.session != null) {
        unawaited(s.refresh());
      } else {
        changed();
      }
    });
    if (s.signedIn) unawaited(s.refresh());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(changed);
    auth?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!s.signedIn) {
      tab = 0;
      workspaceRole = null;
      return WelcomePage(store: s, startupError: widget.startupError);
    }
    if (!s.roleReady) {
      return Scaffold(
        body: SafeArea(
          child: paddedList([
            gap(60),
            const Center(child: BrandMark(size: 56)),
            gap(24),
            heading(
              'Preparing your workspace',
              'Checking your account access.',
            ),
            if (s.loadError == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              info(s.loadError!, icon: Icons.cloud_off),
              gap(),
              FilledButton(
                onPressed: () => s.refresh(),
                child: const Text('Try again'),
              ),
            ],
            gap(24),
            TextButton(
              onPressed: () => s.signOut(),
              child: const Text('Sign out'),
            ),
          ]),
        ),
      );
    }
    if (workspaceRole != s.role) {
      workspaceRole = s.role;
      tab = 0;
    }
    final admin = s.role == 'admin';
    final merchant = s.role == 'merchant';
    final staff = admin || merchant;
    final pages = admin
        ? [
            for (final section in ManagementSection.values.where(
              (section) => section != ManagementSection.redemption,
            ))
              ManagePage(
                key: ValueKey(section),
                store: s,
                section: section,
                onSectionSelected: (section) =>
                    setState(() => tab = section.index),
              ),
          ]
        : merchant
        ? [
            ManagePage(
              key: const ValueKey(ManagementSection.rewards),
              store: s,
              section: ManagementSection.rewards,
            ),
            ManagePage(
              key: const ValueKey(ManagementSection.redemption),
              store: s,
              section: ManagementSection.redemption,
            ),
          ]
        : [
            ExplorePage(store: s, onMission: () => setState(() => tab = 1)),
            MissionPage(
              store: s,
              onWallet: () => setState(() => tab = 2),
              onExplore: () => setState(() => tab = 0),
            ),
            WalletPage(store: s, onExplore: () => setState(() => tab = 0)),
            ProfilePage(store: s),
          ];
    if (tab >= pages.length) tab = 0;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const BrandMark(size: 32),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'langkah',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  fontSize: 24,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              if (staff) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => StaffAccountPage(store: s)),
                );
              } else {
                setState(() => tab = 3);
              }
            },
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: admin
                ? 'Admin account'
                : merchant
                ? 'Merchant account'
                : 'Your profile',
          ),
          IconButton(
            onPressed: s.loading ? null : () => s.refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          if (s.loading) const LinearProgressIndicator(),
          if (s.loadError != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: info(s.loadError!, icon: Icons.cloud_off),
            ),
          Expanded(
            child: IndexedStack(
              key: ValueKey(s.role),
              index: tab,
              children: pages,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: admin
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.space_dashboard_outlined),
                  selectedIcon: Icon(Icons.space_dashboard_rounded),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(Icons.location_city_outlined),
                  selectedIcon: Icon(Icons.location_city_rounded),
                  label: 'Malls',
                ),
                NavigationDestination(
                  icon: Icon(Icons.storefront_outlined),
                  selectedIcon: Icon(Icons.storefront_rounded),
                  label: 'Merchants',
                ),
                NavigationDestination(
                  icon: Icon(Icons.local_offer_outlined),
                  selectedIcon: Icon(Icons.local_offer_rounded),
                  label: 'Rewards',
                ),
                NavigationDestination(
                  icon: Icon(Icons.feedback_outlined),
                  selectedIcon: Icon(Icons.feedback_rounded),
                  label: 'Reports',
                ),
              ]
            : merchant
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.local_offer_outlined),
                  selectedIcon: Icon(Icons.local_offer_rounded),
                  label: 'Offers',
                ),
                NavigationDestination(
                  icon: Icon(Icons.qr_code_scanner),
                  selectedIcon: Icon(Icons.qr_code_rounded),
                  label: 'Redeem',
                ),
              ]
            : const [
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore),
                  label: 'Explore',
                ),
                NavigationDestination(
                  icon: Icon(Icons.directions_walk),
                  label: 'Mission',
                ),
                NavigationDestination(
                  icon: Icon(Icons.confirmation_number_outlined),
                  selectedIcon: Icon(Icons.confirmation_number),
                  label: 'Wallet',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'You',
                ),
              ],
      ),
    );
  }
}

Widget paddedList(List<Widget> children) => Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 650),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
      children: children,
    ),
  ),
);
Widget gap([double h = 16]) => SizedBox(height: h);
Widget heading(String title, String subtitle) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      title,
      style: const TextStyle(
        fontSize: 30,
        height: 1.15,
        fontWeight: FontWeight.w800,
        color: navy,
        letterSpacing: -1,
      ),
    ),
    gap(10),
    Text(
      subtitle,
      style: const TextStyle(fontSize: 14, height: 1.55, color: muted),
    ),
    gap(24),
  ],
);
Widget info(String text, {IconData icon = Icons.info_outline}) => Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: const Color(0xFFEDF2E7),
    borderRadius: BorderRadius.circular(18),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: green, size: 20),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(fontSize: 13, height: 1.55, color: navy),
        ),
      ),
    ],
  ),
);
Widget pill(String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  decoration: BoxDecoration(
    color: lime.withValues(alpha: .4),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: green,
    ),
  ),
);
void message(BuildContext c, String text) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(text)));
String day(String value) {
  final d = DateTime.parse(value).toUtc().add(const Duration(hours: 8));
  return '${d.day}/${d.month}/${d.year}';
}

class WelcomePage extends StatefulWidget {
  final LangkahStore store;
  final String? startupError;
  const WelcomePage({super.key, required this.store, this.startupError});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  bool register = false, busy = false, hidePassword = true;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!email.text.contains('@') || password.text.length < 6) {
      message(
        context,
        'Enter an email and a password of at least six characters.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      if (register) {
        final result = await widget.store.client!.auth.signUp(
          email: email.text.trim(),
          password: password.text,
          emailRedirectTo: 'langkah://auth/callback',
          data: {
            'display_name': name.text.trim().isEmpty
                ? 'Walker'
                : name.text.trim(),
          },
        );
        if (result.session == null && mounted) {
          message(
            context,
            'Check your email to confirm your account, then sign in.',
          );
        }
      } else {
        await widget.store.client!.auth.signInWithPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
      await widget.store.refresh();
    } catch (e) {
      if (mounted) message(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: AutofillGroup(
        child: paddedList([
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandMark(),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'langkah',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.5,
                      ),
                    ),
                  ),
                ],
              ),
              pill('WALK • DISCOVER • EARN'),
            ],
          ),
          gap(24),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: green,
              borderRadius: BorderRadius.circular(28),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Small steps.\nBetter days.',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            height: 1.12,
                            letterSpacing: -1,
                            color: Colors.white,
                          ),
                        ),
                        gap(14),
                        const Text(
                          'Your next reward\nstarts with a walk.',
                          style: TextStyle(
                            color: Color(0xFFE1EDDA),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (constraints.maxWidth > 280 &&
                      MediaQuery.textScalerOf(context).scale(1) < 1.4)
                    const WalkIllustration(),
                ],
              ),
            ),
          ),
          gap(18),
          const Text(
            'Explore your local mall. Walk at your pace.\nChoose a reward from nearby shops.',
            style: TextStyle(fontSize: 14, height: 1.55, color: muted),
          ),
          gap(22),
          if (widget.startupError != null) ...[
            info(widget.startupError!),
            gap(),
          ],
          if (widget.store.client != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: cream,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _authTab(
                              'Sign in',
                              !register,
                              () => setState(() => register = false),
                            ),
                          ),
                          Expanded(
                            child: _authTab(
                              'Create account',
                              register,
                              () => setState(() => register = true),
                            ),
                          ),
                        ],
                      ),
                    ),
                    gap(20),
                    Text(
                      register
                          ? 'Start something good.'
                          : 'Good to see you again.',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.5,
                      ),
                    ),
                    gap(6),
                    Text(
                      register
                          ? 'A few details, then you’re ready to explore.'
                          : 'Sign in to pick up where you left off.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: muted,
                        height: 1.5,
                      ),
                    ),
                    gap(20),
                    if (register) ...[
                      TextField(
                        controller: name,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      gap(12),
                    ],
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.alternate_email_rounded),
                      ),
                    ),
                    gap(12),
                    TextField(
                      controller: password,
                      obscureText: hidePassword,
                      autofillHints: [
                        register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: hidePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () =>
                              setState(() => hidePassword = !hidePassword),
                          icon: Icon(
                            hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      onSubmitted: (_) {
                        if (!busy) submit();
                      },
                    ),
                    if (!register)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: busy
                              ? null
                              : () => Navigator.push(
                                  c,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        RecoveryPage(store: widget.store),
                                  ),
                                ),
                          child: const Text('Forgot password?'),
                        ),
                      )
                    else ...[
                      gap(12),
                      const Text(
                        'Use at least 6 characters.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      gap(12),
                    ],
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (busy) ...[
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Flexible(
                            child: Text(
                              busy
                                  ? 'Connecting…'
                                  : register
                                  ? 'Create account'
                                  : 'Sign in',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (!busy) ...[
                            const SizedBox(width: 12),
                            const Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              try {
                                await widget.store.client!.auth.resend(
                                  type: OtpType.signup,
                                  email: email.text.trim(),
                                );
                                if (c.mounted) {
                                  message(
                                    c,
                                    'Confirmation email requested. Check your inbox.',
                                  );
                                }
                              } catch (e) {
                                if (c.mounted) message(c, friendlyError(e));
                              }
                            },
                      child: const Text(
                        'Resend account confirmation',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            info(
              'Supabase configuration is missing. Build using config/supabase.local.json.',
            ),
          gap(20),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, size: 16, color: muted),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'You’re in control. Location and step permissions are requested when you start a walk.',
                  style: TextStyle(fontSize: 12, height: 1.5, color: muted),
                ),
              ),
            ],
          ),
        ]),
      ),
    ),
  );
  Widget _authTab(String label, bool selected, VoidCallback onTap) =>
      TextButton(
        onPressed: busy ? null : onTap,
        style: TextButton.styleFrom(
          backgroundColor: selected ? Colors.white : Colors.transparent,
          foregroundColor: selected ? green : muted,
          minimumSize: const Size(48, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13),
        ),
      );
}

class ExplorePage extends StatelessWidget {
  final LangkahStore store;
  final VoidCallback onMission;
  const ExplorePage({super.key, required this.store, required this.onMission});
  Future<void> start(BuildContext c, JsonMap r) async {
    String? code;
    if (store.session == null &&
        store.mallFor(r['mall_id'])?['qr_required'] == true) {
      code = await scanCode(c, 'Scan staff start QR');
      if (code == null || !c.mounted) return;
    }
    showDialog(
      context: c,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Checking your visit…')),
          ],
        ),
      ),
    );
    try {
      await WalkingDevice.requestActivity();
      final location = await WalkingDevice.location();
      await store.start(r, location: location, code: code);
      if (c.mounted) {
        Navigator.pop(c);
        onMission();
      }
    } catch (e) {
      if (c.mounted) {
        Navigator.pop(c);
        message(c, friendlyError(e));
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final m = store.mallFor(store.selectedMall);
    final offers = store.offersAt(store.selectedMall);
    return paddedList([
      Text(
        'LET’S MAKE TODAY COUNT',
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w700,
          color: muted,
        ),
      ),
      gap(8),
      heading(
        'Hello, ${store.name.split(' ').first}.',
        'A little movement. Something to look forward to.',
      ),
      if (store.malls.isEmpty)
        info('Loading malls. Use Refresh if your connection was interrupted.'),
      if (store.malls.isNotEmpty)
        DropdownButtonFormField<String>(
          key: ValueKey(store.selectedMall),
          initialValue: store.selectedMall,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Your destination',
            prefixIcon: Icon(Icons.location_on_outlined),
            fillColor: Colors.white,
          ),
          items: store.malls
              .map(
                (m) => DropdownMenuItem<String>(
                  value: m['id'],
                  child: Text(
                    m['name'],
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) store.selectMall(v);
          },
        ),
      gap(18),
      if (m != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Container(
            decoration: BoxDecoration(
              color: green,
              image: m['id'] == 'elmina'
                  ? const DecorationImage(
                      image: ResizeImage(
                        AssetImage('assets/elmina.jpg'),
                        width: 1200,
                      ),
                      fit: BoxFit.cover,
                      alignment: Alignment(-.3, 0),
                    )
                  : null,
            ),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    green.withValues(alpha: .18),
                    const Color(0xF2163028),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'EXPLORE A LITTLE CLOSER',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  gap(m['id'] == 'elmina' ? 52 : 24),
                  Text(
                    m['name'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                    ),
                  ),
                  gap(10),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: lime,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          m['area'] ?? m['address'],
                          style: const TextStyle(
                            color: Color(0xFFDAE5D9),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      gap(12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.my_location_rounded, color: green, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              m?['qr_required'] == true
                  ? 'Location + staff QR checked when you start'
                  : 'Your location is checked when you start',
              style: const TextStyle(fontSize: 12, color: muted),
            ),
          ),
        ],
      ),
      gap(16),
      sectionTitle(
        'Choose your mission',
        detail:
            '${store.mallRoutes.length} ${store.mallRoutes.length == 1 ? 'walk' : 'walks'}',
      ),
      if (store.mallRoutes.isEmpty)
        const EmptyState(
          icon: Icons.route_outlined,
          title: 'Walks are on the way',
          body: 'Missions will appear here when this mall’s routes are ready.',
        ),
      ...store.mallRoutes.map(
        (r) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      iconBadge(
                        Icons.directions_walk_rounded,
                        background: lime.withValues(alpha: .4),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r['name'],
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                                letterSpacing: -.4,
                              ),
                            ),
                            gap(8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                pill('~ ${r['minutes']} min'),
                                pill(
                                  r['active'] == true &&
                                          m?['geofence_reviewed'] == true
                                      ? 'Open'
                                      : 'Coming soon',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  gap(20),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        '${r['target_steps']}',
                        style: const TextStyle(
                          fontSize: 34,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const Text(
                        'steps at your pace',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                  gap(14),
                  Text(
                    r['description'],
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: muted,
                    ),
                  ),
                  gap(18),
                  FilledButton(
                    onPressed:
                        r['active'] == true && m?['geofence_reviewed'] == true
                        ? () => start(c, r)
                        : null,
                    child: Text(
                      store.session?['route_id'] == r['id']
                          ? 'Continue mission'
                          : 'Start this mission',
                    ),
                  ),
                  Theme(
                    data: Theme.of(
                      c,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      title: const Text(
                        'Route & accessibility',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            r['accessibility'],
                            style: const TextStyle(
                              color: muted,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      sectionTitle('Rewards nearby', detail: '${offers.length} available'),
      if (offers.isEmpty)
        const EmptyState(
          icon: Icons.local_offer_outlined,
          title: 'Good things are on the way',
          body:
              'Shop rewards will appear here once offers are approved. Check back before your next walk.',
        ),
      ...offers.map(
        (o) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            child: ListTile(
              leading: iconBadge(shopIcon(store.shopLabel(o['merchant_id']))),
              title: Text(o['title']),
              subtitle: Text(
                '${store.shopLabel(o['merchant_id'])}\n${o['terms']}',
              ),
            ),
          ),
        ),
      ),
      gap(16),
      sectionTitle(
        'Around the mall',
        detail: '${store.mallShops.length} listed shops',
      ),
      ...store.mallShops.map(
        (shop) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: ListTile(
              leading: iconBadge(shopIcon(shop['name'])),
              title: Text(shop['name']),
              subtitle: Text('Lot ${shop['lot']}'),
              trailing: const Icon(
                Icons.north_east_rounded,
                size: 18,
                color: muted,
              ),
              onTap: () async {
                try {
                  await WalkingDevice.openUrl(shop['source_url']);
                } catch (e) {
                  if (c.mounted) message(c, friendlyError(e));
                }
              },
            ),
          ),
        ),
      ),
      gap(8),
      const Text(
        'Official directory listings. Rewards are available only from participating shops.',
        style: TextStyle(fontSize: 12, height: 1.5, color: muted),
      ),
      if (m != null)
        TextButton.icon(
          onPressed: () async {
            try {
              await WalkingDevice.openUrl(m['source_url']);
            } catch (e) {
              if (c.mounted) message(c, friendlyError(e));
            }
          },
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Official mall directory'),
        ),
      gap(12),
      info(
        'Keep Langkah open during your walk. GPS checks proximity; it cannot identify your exact indoor floor.',
        icon: Icons.shield_outlined,
      ),
    ]);
  }
}

class MissionPage extends StatefulWidget {
  final LangkahStore store;
  final VoidCallback onWallet;
  final VoidCallback? onExplore;
  const MissionPage({
    super.key,
    required this.store,
    required this.onWallet,
    this.onExplore,
  });
  @override
  State<MissionPage> createState() => _MissionPageState();
}

class _MissionPageState extends State<MissionPage> with WidgetsBindingObserver {
  StreamSubscription<int>? sensor;
  Timer? syncTimer;
  StepAccumulator counter = StepAccumulator();
  bool tracking = false, busy = false, syncing = false;
  Completer<void>? pendingSync;
  String? sensorError, trackedId;
  LangkahStore get s => widget.store;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    s.addListener(changed);
  }

  void changed() {
    if (tracking && s.session?['id'] != trackedId) {
      unawaited(stop(flush: false));
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    s.removeListener(changed);
    sensor?.cancel();
    syncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && tracking) unawaited(stop());
  }

  Future<void> startTracking() async {
    if (s.session == null) return;
    setState(() => busy = true);
    try {
      await WalkingDevice.requestActivity();
      await s.progress(
        s.session!['steps'] as int,
        await WalkingDevice.location(),
      );
      await WalkingDevice.keepAwake(true);
      counter = StepAccumulator(s.session!['steps'] as int);
      trackedId = s.session!['id'];
      sensor = WalkingDevice.steps.listen(
        (v) {
          counter.addReading(v);
          if (mounted) setState(() {});
        },
        onError: (Object e) {
          sensorError = friendlyError(e);
          unawaited(stop());
        },
      );
      syncTimer = Timer.periodic(const Duration(seconds: 15), (_) => sync());
      setState(() {
        tracking = true;
        sensorError = null;
      });
    } catch (e) {
      sensorError = friendlyError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sync() async {
    if (syncing || s.session == null || trackedId != s.session!['id']) return;
    syncing = true;
    final completion = Completer<void>();
    pendingSync = completion;
    try {
      final location = await WalkingDevice.location();
      await s.progress(counter.steps, location);
    } catch (e) {
      sensorError = friendlyError(e);
      await stop(flush: false);
    } finally {
      syncing = false;
      completion.complete();
      pendingSync = null;
      if (mounted) setState(() {});
    }
  }

  Future<void> stop({bool flush = true}) async {
    syncTimer?.cancel();
    syncTimer = null;
    await sensor?.cancel();
    sensor = null;
    tracking = false;
    await WalkingDevice.keepAwake(false);
    if (flush) {
      await pendingSync?.future;
      await sync();
    }
    trackedId = null;
    if (mounted) setState(() {});
  }

  Future<void> act(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) message(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> checkpoint() async {
    await stop();
    if (!mounted) return;
    final code = await scanCode(context, 'Scan staff finish QR');
    if (code != null) {
      await act(() async => s.checkpoint(code, await WalkingDevice.location()));
    }
  }

  Future<void> rewards() async {
    await stop();
    if (!mounted) return;
    final routeId = s.session!['route_id'] as String;
    final voucher = await Navigator.push<JsonMap>(
      context,
      MaterialPageRoute(builder: (_) => RewardPage(store: s)),
    );
    if (voucher != null && mounted) {
      widget.onWallet();
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VoucherPage(store: s, voucher: voucher),
        ),
      );
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReportPage(store: s, routeId: routeId),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final session = s.session;
    if (session == null) {
      return paddedList([
        heading(
          'Make time for a little walk.',
          'An achievable goal. A reward to look forward to.',
        ),
        EmptyState(
          icon: Icons.directions_walk_rounded,
          title: 'Your next walk starts here',
          body:
              'Choose a mission at your local mall. Your steps and progress will appear here.',
          action: widget.onExplore == null
              ? null
              : FilledButton.icon(
                  onPressed: widget.onExplore,
                  icon: const Icon(Icons.explore_outlined),
                  label: const Text('Find a walking mission'),
                ),
        ),
        gap(24),
        sectionTitle('A walk in three small steps'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: iconBadge(Icons.location_on_outlined),
                title: const Text('Pick your place'),
                subtitle: const Text(
                  'Choose a mall and an achievable mission.',
                ),
              ),
              const Divider(indent: 80, endIndent: 20, height: 1),
              ListTile(
                leading: iconBadge(Icons.directions_walk_rounded),
                title: const Text('Move at your pace'),
                subtitle: const Text('Keep Langkah open. Take breaks freely.'),
              ),
              const Divider(indent: 80, endIndent: 20, height: 1),
              ListTile(
                leading: iconBadge(Icons.card_giftcard_outlined),
                title: const Text('Choose your reward'),
                subtitle: const Text(
                  'Pick an available offer when you finish.',
                ),
              ),
            ],
          ),
        ),
        gap(22),
        info(
          'Your progress is saved when you pause. Resume your mission when you return to the app.',
          icon: Icons.pause_circle_outline,
        ),
      ]);
    }
    final r = s.routeFor(session['route_id']);
    if (r == null) {
      return paddedList([
        info('Your route is unavailable. Refresh or cancel this mission.'),
        TextButton(
          onPressed: () => s.cancel(),
          child: const Text('Cancel mission'),
        ),
      ]);
    }
    final steps = tracking ? counter.steps : session['steps'] as int,
        target = r['target_steps'] as int,
        checkpoints = session['checkpoint_count'] as int;
    final eligible = session['status'] == 'eligible';
    return paddedList([
      heading(
        r['name'],
        s.mallFor(r['mall_id'])?['name'] ??
            'Your movement counts during this visit.',
      ),
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: green,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          children: [
            Text(
              eligible
                  ? 'YOU DID IT!'
                  : tracking
                  ? 'ONE STEP AT A TIME'
                  : 'READY WHEN YOU ARE',
              style: const TextStyle(
                color: lime,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            gap(24),
            SizedBox(
              width: 224,
              height: 224,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: (steps / target).clamp(0, 1),
                      strokeWidth: 12,
                      strokeCap: StrokeCap.round,
                      color: lime,
                      backgroundColor: Colors.white.withValues(alpha: .12),
                      semanticsLabel: 'Walking progress',
                      semanticsValue: '$steps of $target steps',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.directions_walk_rounded,
                          color: lime,
                          size: 28,
                        ),
                        gap(10),
                        FittedBox(
                          child: Text(
                            '$steps',
                            style: const TextStyle(
                              fontSize: 58,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1,
                              letterSpacing: -2,
                            ),
                          ),
                        ),
                        gap(10),
                        Text(
                          'of $target steps',
                          style: const TextStyle(
                            color: Color(0xFFDCE8DA),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            gap(24),
            Text(
              eligible
                  ? 'Your reward is ready to choose.'
                  : '${(target - steps).clamp(0, target)} steps to your goal',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      gap(16),
      Row(
        children: [
          Expanded(
            child: StatTile(
              value: '~ ${(steps * .7).round()} m',
              label: 'Estimated distance',
              icon: Icons.route_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatTile(
              value: '${r['minutes']} min',
              label: 'Suggested walk',
              icon: Icons.schedule_outlined,
            ),
          ),
        ],
      ),
      gap(18),
      if (session['qr_required'] == true)
        Card(
          child: ListTile(
            leading: const Icon(Icons.qr_code, color: green),
            title: Text('$checkpoints of 2 staff checkpoints confirmed'),
            subtitle: const Text(
              'Scan the finish QR after reaching your step goal.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap:
                busy || checkpoints >= 2 || (session['steps'] as int) < target
                ? null
                : checkpoint,
          ),
        ),
      gap(12),
      if (sensorError != null) ...[
        info(sensorError!, icon: Icons.warning_amber_rounded),
        gap(),
      ],
      if (!eligible) ...[
        FilledButton.icon(
          onPressed: busy
              ? null
              : tracking
              ? () => stop()
              : startTracking,
          icon: Icon(tracking ? Icons.pause : Icons.play_arrow),
          label: Text(tracking ? 'Pause walking' : 'Resume step tracking'),
        ),
        gap(8),
        const Text(
          'Keep this app open while walking. Take breaks freely.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Color(0xFF64716B)),
        ),
      ],
      gap(16),
      FilledButton.icon(
        onPressed: busy || !eligible ? null : rewards,
        icon: const Icon(Icons.card_giftcard),
        label: const Text('Choose my reward'),
      ),
      gap(8),
      TextButton.icon(
        onPressed: () => Navigator.push(
          c,
          MaterialPageRoute(
            builder: (_) => ReportPage(store: s, routeId: r['id']),
          ),
        ),
        icon: const Icon(Icons.report_outlined),
        label: const Text('Report a route issue'),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () => act(() async {
                await stop();
                await s.cancel();
              }),
        child: const Text('Cancel this mission'),
      ),
    ]);
  }
}

class RewardPage extends StatefulWidget {
  final LangkahStore store;
  const RewardPage({super.key, required this.store});
  @override
  State<RewardPage> createState() => _RewardPageState();
}

class _RewardPageState extends State<RewardPage> {
  bool busy = false;
  @override
  Widget build(BuildContext c) => ListenableBuilder(
    listenable: widget.store,
    builder: (c, _) => Scaffold(
      appBar: AppBar(title: const Text('Choose your reward')),
      body: paddedList([
        const Center(child: BrandMark(size: 56)),
        gap(20),
        heading(
          'A reward, well earned.',
          'Pick one available reward. One mission unlocks one voucher.',
        ),
        if (widget.store.availableOffers.isEmpty)
          info(
            'All rewards are currently out of stock. Your eligible mission is saved. Check again later.',
          ),
        ...widget.store.availableOffers.map(
          (o) => Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      iconBadge(
                        shopIcon(widget.store.shopLabel(o['merchant_id'])),
                        background: lime.withValues(alpha: .4),
                      ),
                      const Spacer(),
                      pill('${o['stock']} left'),
                    ],
                  ),
                  gap(20),
                  Text(
                    o['title'],
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: navy,
                    ),
                  ),
                  gap(8),
                  Text(widget.store.shopLabel(o['merchant_id'])),
                  gap(14),
                  Text(
                    o['terms'],
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                  gap(20),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() => busy = true);
                            try {
                              final voucher = await widget.store.claim(o['id']);
                              if (c.mounted) Navigator.pop(c, voucher);
                            } catch (e) {
                              if (c.mounted) message(c, friendlyError(e));
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    child: Text(busy ? 'Claiming…' : 'Choose this reward'),
                  ),
                ],
              ),
            ),
          ),
        ),
        info(
          'Up to two rewards each day, subject to shop stock. You can continue walking after reaching the reward limit.',
        ),
      ]),
    ),
  );
}

class WalletPage extends StatelessWidget {
  final LangkahStore store;
  final VoidCallback? onExplore;
  const WalletPage({super.key, required this.store, this.onExplore});
  @override
  Widget build(BuildContext c) {
    final available = store.myVouchers
        .where((v) => store.status(v) == 'Available')
        .length;
    return paddedList([
      heading(
        'A little walk. A little win.',
        'Your earned rewards, all in one place.',
      ),
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: green,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'READY TO ENJOY',
                    style: TextStyle(
                      color: lime,
                      fontSize: 10,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  gap(12),
                  Text(
                    '$available',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  gap(6),
                  const Text(
                    'available rewards',
                    style: TextStyle(color: Color(0xFFDCE8DA), fontSize: 13),
                  ),
                ],
              ),
            ),
            iconBadge(
              Icons.confirmation_number_outlined,
              color: lime,
              background: Colors.white.withValues(alpha: .1),
              size: 64,
            ),
          ],
        ),
      ),
      gap(22),
      sectionTitle(
        'Your vouchers',
        detail: '${store.myVouchers.length} collected',
      ),
      if (store.myVouchers.isEmpty)
        EmptyState(
          icon: Icons.confirmation_number_outlined,
          title: 'Your first win is waiting',
          body:
              'Complete a walking mission and choose an available reward. We’ll keep it right here.',
          action: onExplore == null
              ? null
              : FilledButton.icon(
                  onPressed: onExplore,
                  icon: const Icon(Icons.directions_walk_rounded),
                  label: const Text('Explore walking missions'),
                ),
        ),
      ...store.myVouchers.map((v) {
        final offer = store.offerFor(v['offer_id']);
        return TicketCard(
          title: v['title_snapshot'] ?? offer?['title'] ?? 'Shop reward',
          merchant:
              v['merchant_snapshot'] ?? store.shopLabel(offer?['merchant_id']),
          footer: 'Expires ${day(v['expires_at'])}',
          status: store.status(v),
          onTap: () => Navigator.push(
            c,
            MaterialPageRoute(
              builder: (_) => VoucherPage(store: store, voucher: v),
            ),
          ),
        );
      }),
      gap(18),
      info(
        'Show your voucher QR to authorised shop staff. Each reward can be used once.',
        icon: Icons.qr_code_rounded,
      ),
    ]);
  }
}

class VoucherPage extends StatefulWidget {
  final LangkahStore store;
  final JsonMap voucher;
  const VoucherPage({super.key, required this.store, required this.voucher});
  @override
  State<VoucherPage> createState() => _VoucherPageState();
}

class _VoucherPageState extends State<VoucherPage> with WidgetsBindingObserver {
  Timer? timer;
  bool fetching = false;
  String? syncError;
  LangkahStore get store => widget.store;
  JsonMap get voucher =>
      store.vouchers
          .where((v) => v['id'] == widget.voucher['id'])
          .firstOrNull ??
      widget.voucher;
  @override
  void initState() {
    super.initState();
    store.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
    startPolling();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void startPolling() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (fetching || store.client == null || !store.signedIn) return;
    fetching = true;
    try {
      await store.refreshVoucher(widget.voucher['id']);
      syncError = null;
    } catch (e) {
      syncError = 'Could not refresh voucher. ${friendlyError(e)}';
    } finally {
      fetching = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      startPolling();
    } else if (state == AppLifecycleState.paused) {
      timer?.cancel();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    store.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final o = store.offerFor(voucher['offer_id']),
        available = store.status(voucher) == 'Available';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your voucher'),
        actions: [
          IconButton(
            onPressed: fetching ? null : refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh voucher',
          ),
        ],
      ),
      body: paddedList([
        if (syncError != null) info(syncError!),
        heading(
          voucher['title_snapshot'] ?? o?['title'] ?? 'Shop reward',
          voucher['merchant_snapshot'] ?? store.shopLabel(o?['merchant_id']),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                pill(store.status(voucher)),
                gap(24),
                if (available)
                  QrImageView(
                    data: voucher['code'],
                    version: QrVersions.auto,
                    size: 220,
                    backgroundColor: Colors.white,
                    semanticsLabel: 'Voucher redemption QR code',
                  )
                else
                  const Icon(
                    Icons.check_circle_outline,
                    size: 100,
                    color: green,
                  ),
                gap(20),
                SelectableText(
                  voucher['code'],
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: navy,
                  ),
                ),
                gap(14),
                Text(
                  'Expires ${day(voucher['expires_at'])}',
                  style: const TextStyle(color: Color(0xFF64716B)),
                ),
              ],
            ),
          ),
        ),
        gap(20),
        Text(
          voucher['terms_snapshot'] ??
              o?['terms'] ??
              'Check the shop terms before redeeming.',
          style: const TextStyle(height: 1.6),
        ),
        gap(20),
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: voucher['code']));
            message(c, 'Voucher code copied.');
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy voucher code'),
        ),
        gap(),
        info(
          'Show this code to authorised shop staff. Each voucher can be redeemed once.',
        ),
      ]),
    );
  }
}

class ReportPage extends StatefulWidget {
  final LangkahStore store;
  final String routeId;
  const ReportPage({super.key, required this.store, required this.routeId});
  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final description = TextEditingController();
  String category = 'Obstruction';
  bool busy = false;
  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Route feedback')),
    body: paddedList([
      heading(
        'Make the next walk easier.',
        'Share a walking barrier for the township team to review.',
      ),
      DropdownButtonFormField<String>(
        initialValue: category,
        decoration: const InputDecoration(labelText: 'Type of issue'),
        items: [
          'Obstruction',
          'Directions',
          'Rest points',
          'Accessibility',
          'Other',
        ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => category = v!),
      ),
      gap(),
      TextField(
        controller: description,
        maxLines: 5,
        maxLength: 1000,
        decoration: const InputDecoration(
          labelText: 'What happened?',
          hintText: 'Describe the spot and what made the walk difficult.',
        ),
      ),
      gap(),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                setState(() => busy = true);
                try {
                  await widget.store.report(
                    widget.routeId,
                    category,
                    description.text,
                  );
                  if (c.mounted) {
                    Navigator.pop(c);
                    message(c, 'Your report is saved for review.');
                  }
                } catch (e) {
                  if (c.mounted) message(c, friendlyError(e));
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        child: Text(busy ? 'Saving…' : 'Submit feedback'),
      ),
      gap(),
      info(
        'Please avoid names, contact details or medical information. This form is for route improvements, not urgent assistance.',
      ),
    ]),
  );
}

class StaffAccountPage extends StatelessWidget {
  final LangkahStore store;
  const StaffAccountPage({super.key, required this.store});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(
          store.role == 'admin' ? 'Admin account' : 'Merchant account',
        ),
      ),
      body: paddedList([
        heading(
          'Your account',
          'Account details and access to your management workspace.',
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.person_outline, color: green),
                title: Text(store.name),
                subtitle: const Text('Account name'),
              ),
              if (store.email != null)
                ListTile(
                  leading: const Icon(Icons.alternate_email, color: green),
                  title: Text(store.email!),
                  subtitle: const Text('Email address'),
                ),
              ListTile(
                leading: const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: green,
                ),
                title: Text(
                  store.role == 'admin'
                      ? 'Township administrator'
                      : 'Outlet representative',
                ),
                subtitle: const Text('Access assigned by Langkah'),
              ),
              if (store.role == 'merchant')
                ListTile(
                  leading: const Icon(Icons.storefront_outlined, color: green),
                  title: Text(store.shopLabel(store.assignedMerchant)),
                  subtitle: Text(
                    store.mallFor(
                          store.merchantFor(store.assignedMerchant)?['mall_id'],
                        )?['name'] ??
                        'Assigned outlet',
                  ),
                ),
            ],
          ),
        ),
        gap(24),
        OutlinedButton.icon(
          onPressed: store.loading ? null : () => store.refresh(),
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh account access'),
        ),
        gap(12),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RecoveryPage(store: store)),
          ),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Request password reset'),
        ),
        gap(24),
        FilledButton.icon(
          onPressed: () async {
            try {
              await store.signOut();
              if (context.mounted) Navigator.pop(context);
            } catch (error) {
              if (context.mounted) message(context, friendlyError(error));
            }
          },
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ]),
    ),
  );
}

class ProfilePage extends StatelessWidget {
  final LangkahStore store;
  const ProfilePage({super.key, required this.store});
  @override
  Widget build(BuildContext c) {
    final ownHistory = store.history
            .where((s) => s['user_id'] == store.userId)
            .toList(),
        completed = ownHistory.where((s) => s['status'] == 'claimed').toList();
    final days = completed.map((s) => day(s['started_at'])).toSet().length;
    return paddedList([
      heading(
        'Your routine, your pace.',
        'Every little walk is a step in a good direction.',
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: lime,
                child: Text(
                  store.name.isEmpty
                      ? 'W'
                      : store.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 24,
                    color: green,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    gap(6),
                    Text(
                      store.role == 'admin'
                          ? 'Township administrator'
                          : store.role == 'merchant'
                          ? 'Merchant account'
                          : 'Your walking companion',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      gap(16),
      Row(
        children: [
          Expanded(
            child: StatTile(
              value: '$days',
              label: 'Active days',
              icon: Icons.wb_sunny_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatTile(
              value: '${completed.length}',
              label: 'Finished missions',
              icon: Icons.check_circle_outline,
            ),
          ),
        ],
      ),
      gap(22),
      Card(
        child: ExpansionTile(
          leading: const Icon(Icons.shield_outlined, color: green),
          title: const Text(
            'Your movement, your privacy',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            'How location and steps are used',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: const [
            Text(
              'Activity permission counts steps. Location is checked during each walk. Tracking pauses in the background or if verification fails. Only the most recent mission location is stored.',
              style: TextStyle(fontSize: 13, height: 1.6, color: muted),
            ),
          ],
        ),
      ),
      gap(20),
      if (store.role == 'resident')
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            c,
            MaterialPageRoute(
              builder: (_) => MerchantRequestPage(store: store),
            ),
          ),
          icon: const Icon(Icons.storefront),
          label: const Text('Request merchant access'),
        ),
      gap(),
      const Text(
        'Recent missions',
        style: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          color: navy,
        ),
      ),
      gap(12),
      if (completed.isEmpty)
        const EmptyState(
          icon: Icons.route_outlined,
          title: 'A fresh start',
          body:
              'Your completed walks will appear here. Build a routine that works for you.',
        ),
      ...completed
          .take(8)
          .map(
            (s) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_outline, color: green),
              title: Text(store.routeFor(s['route_id'])?['name'] ?? 'Mission'),
              subtitle: Text('${s['steps']} steps • ${day(s['started_at'])}'),
            ),
          ),
      gap(),
      OutlinedButton.icon(
        onPressed: () => store.signOut(),
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
      ),
      gap(24),
      const Text(
        'Langkah • Active visits, local rewards. Mall and shop listings checked against official directories on 11 October 2026.',
        style: TextStyle(fontSize: 11, height: 1.4, color: Color(0xFF64716B)),
      ),
    ]);
  }
}

Future<String?> scanCode(BuildContext c, String title) =>
    Navigator.push<String>(
      c,
      MaterialPageRoute(builder: (_) => ScannerPage(title: title)),
    );

class ScannerPage extends StatefulWidget {
  final String title;
  const ScannerPage({super.key, required this.title});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final manual = TextEditingController();
  bool returned = false;
  @override
  void dispose() {
    manual.dispose();
    super.dispose();
  }

  void finish(String code) {
    if (returned || code.trim().isEmpty) return;
    returned = true;
    Navigator.pop(context, code.trim());
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                final code = capture.barcodes.firstOrNull?.rawValue;
                if (code != null) finish(code);
              },
              errorBuilder: (c, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Camera unavailable. Allow camera access in Android Settings, or enter the code below. ${error.errorCode.name}',
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                TextField(
                  controller: manual,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Or enter the code',
                  ),
                ),
                gap(12),
                FilledButton(
                  onPressed: () => finish(manual.text),
                  child: const Text('Use this code'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class MerchantRequestPage extends StatefulWidget {
  final LangkahStore store;
  const MerchantRequestPage({super.key, required this.store});
  @override
  State<MerchantRequestPage> createState() => _MerchantRequestPageState();
}

class _MerchantRequestPageState extends State<MerchantRequestPage> {
  String? merchant;
  final contact = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    contact.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Merchant access')),
    body: paddedList([
      heading(
        'Represent a shop?',
        'Choose your outlet and provide a business contact. An administrator must verify your authority before granting access.',
      ),
      ...widget.store.requests.map(
        (r) => info(
          '${widget.store.shopLabel(r['merchant_id'])} • ${r['status']}',
        ),
      ),
      gap(),
      DropdownButtonFormField<String>(
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Your outlet'),
        items: widget.store.merchants
            .map(
              (m) => DropdownMenuItem<String>(
                value: m['id'],
                child: Text(
                  '${m['name']} • ${widget.store.mallFor(m['mall_id'])?['name']}',
                ),
              ),
            )
            .toList(),
        onChanged: (v) => merchant = v,
      ),
      gap(),
      TextField(
        controller: contact,
        maxLength: 300,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Business email / phone and your role',
        ),
      ),
      gap(),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                if (merchant == null) {
                  message(c, 'Choose an outlet.');
                  return;
                }
                setState(() => busy = true);
                try {
                  await widget.store.requestMerchant(merchant!, contact.text);
                  if (c.mounted) {
                    Navigator.pop(c);
                    message(
                      c,
                      'Request saved. An administrator will review it.',
                    );
                  }
                } catch (e) {
                  if (c.mounted) message(c, friendlyError(e));
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        child: Text(busy ? 'Submitting…' : 'Request access'),
      ),
    ]),
  );
}

enum ManagementSection {
  overview,
  malls,
  merchants,
  rewards,
  reports,
  redemption,
}

class ManagePage extends StatefulWidget {
  final LangkahStore store;
  final ManagementSection? section;
  final ValueChanged<ManagementSection>? onSectionSelected;
  const ManagePage({
    super.key,
    required this.store,
    this.section,
    this.onSectionSelected,
  });
  @override
  State<ManagePage> createState() => _ManagePageState();
}

class _ManagePageState extends State<ManagePage> {
  final code = TextEditingController();
  bool busy = false;
  LangkahStore get s => widget.store;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> act(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) message(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> stock(JsonMap o) async {
    final input = TextEditingController(text: '${o['stock']}');
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Voucher stock'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Remaining quantity'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, input.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value != null) {
      await act(() async {
        final qty = int.tryParse(value);
        if (qty == null) throw StateError('Enter a whole number.');
        await s.setOffer(o, qty, o['active'] == true);
      });
    }
  }

  Future<void> approve(JsonMap o) async {
    final ref = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Publish approved offer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.shopLabel(o['merchant_id'])),
              gap(),
              Text(o['title']),
              gap(),
              Text(o['terms']),
              gap(),
              Text(
                'Campaign ends ${day(o['ends_at'])}. Stock ${o['stock']}. Voucher validity ${o['valid_days']} days.',
              ),
              gap(),
              TextField(
                controller: ref,
                maxLength: 300,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Merchant approval reference',
                  hintText: 'Agreement date / authorised contact / reference',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ref.text),
            child: const Text('Approve and publish'),
          ),
        ],
      ),
    );
    ref.dispose();
    if (value != null) await act(() => s.approveOffer(o, true, value));
  }

  Future<void> review(JsonMap q) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Grant outlet access?'),
        content: Text(
          '${s.shopLabel(q['merchant_id'])}\n\n${q['contact']}\n\nGrant access only after verifying this person represents the outlet. They will be able to submit offers and redeem this outlet’s vouchers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Verified: approve'),
          ),
        ],
      ),
    );
    if (yes != null) await act(() => s.reviewMerchant(q['user_id'], yes));
  }

  @override
  Widget build(BuildContext c) {
    final admin = s.role == 'admin';
    final activeDays = <String, Set<String>>{};
    for (final w in s.history.where((w) => w['status'] == 'claimed')) {
      activeDays.putIfAbsent(w['user_id'], () => {}).add(day(w['started_at']));
    }
    bool show(ManagementSection section) =>
        widget.section == null || widget.section == section;
    final titles = {
      ManagementSection.overview: (
        'Township dashboard',
        'A clear view of activity and the things that need attention.',
      ),
      ManagementSection.malls: (
        'Malls & walking routes',
        'Review locations, open routes and manage staff check-in QR codes.',
      ),
      ManagementSection.merchants: (
        'Merchant access',
        'Verify shop representatives before granting outlet access.',
      ),
      ManagementSection.rewards: (
        'Shop rewards',
        'Review offers, control stock and support voucher redemption.',
      ),
      ManagementSection.reports: (
        'Community reports',
        'Review walking barriers and track their resolution.',
      ),
    };
    final title = titles[widget.section] ?? titles[ManagementSection.overview]!;
    return paddedList([
      heading(
        admin
            ? title.$1
            : widget.section == ManagementSection.redemption
            ? 'Voucher redemption'
            : 'Your shop offers',
        admin ? title.$2 : s.shopLabel(s.assignedMerchant),
      ),
      if (admin && show(ManagementSection.overview)) ...[
        Row(
          children: [
            Expanded(
              child: StatTile(
                value:
                    '${s.history.where((w) => w['status'] == 'claimed').length}',
                label: 'Completed walks',
                icon: Icons.directions_walk_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                value: '${s.vouchers.length}',
                label: 'Rewards issued',
                icon: Icons.local_offer_outlined,
              ),
            ),
          ],
        ),
        gap(12),
        Row(
          children: [
            Expanded(
              child: StatTile(
                value:
                    '${s.vouchers.where((v) => v['redeemed_at'] != null).length}',
                label: 'Rewards redeemed',
                icon: Icons.qr_code_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                value:
                    '${activeDays.values.where((d) => d.length >= 2).length}',
                label: 'Repeat walkers',
                icon: Icons.people_outline,
              ),
            ),
          ],
        ),

        gap(24),
        sectionTitle('Needs your attention'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: iconBadge(Icons.storefront_outlined),
                title: const Text('Merchant requests'),
                subtitle: Text(
                  '${s.requests.where((q) => q['status'] == 'pending').length} waiting for review',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onSectionSelected == null
                    ? null
                    : () => widget.onSectionSelected!(
                        ManagementSection.merchants,
                      ),
              ),
              const Divider(indent: 80, endIndent: 20, height: 1),
              ListTile(
                leading: iconBadge(Icons.local_offer_outlined),
                title: const Text('Pending offers'),
                subtitle: Text(
                  '${s.staffOffers.where((o) => o['approval'] == 'pending').length} waiting for approval',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onSectionSelected == null
                    ? null
                    : () =>
                          widget.onSectionSelected!(ManagementSection.rewards),
              ),
              const Divider(indent: 80, endIndent: 20, height: 1),
              ListTile(
                leading: iconBadge(Icons.feedback_outlined),
                title: const Text('Open route issues'),
                subtitle: Text(
                  '${s.reports.where((r) => r['resolved'] != true).length} to follow up',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onSectionSelected == null
                    ? null
                    : () =>
                          widget.onSectionSelected!(ManagementSection.reports),
              ),
              const Divider(indent: 80, endIndent: 20, height: 1),
              ListTile(
                leading: iconBadge(Icons.location_city_outlined),
                title: const Text('Mall setup'),
                subtitle: Text(
                  '${s.malls.where((m) => m['geofence_reviewed'] != true).length} boundaries need review',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onSectionSelected == null
                    ? null
                    : () => widget.onSectionSelected!(ManagementSection.malls),
              ),
            ],
          ),
        ),
      ],
      if ((admin && show(ManagementSection.rewards)) ||
          (!admin && show(ManagementSection.redemption))) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Redeem a voucher',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                gap(),
                TextField(
                  controller: code,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Visitor’s voucher code',
                  ),
                ),
                gap(),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final value = await scanCode(c, 'Scan voucher');
                          if (value != null) code.text = value;
                        },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan voucher'),
                ),
                gap(),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => act(() async {
                          final v = await s.redeem(code.text);
                          code.clear();
                          if (c.mounted) {
                            message(
                              c,
                              'Redeemed: ${v['title_snapshot'] ?? 'voucher'}',
                            );
                          }
                        }),
                  child: Text(busy ? 'Checking…' : 'Validate and redeem'),
                ),
              ],
            ),
          ),
        ),
      ],
      if (show(ManagementSection.rewards)) ...[
        if (admin) ...[gap(24), sectionTitle('Shop offers')],
        FilledButton.icon(
          onPressed: busy
              ? null
              : () => Navigator.push(
                  c,
                  MaterialPageRoute(builder: (_) => OfferEditorPage(store: s)),
                ),
          icon: const Icon(Icons.add),
          label: const Text('Create an offer for approval'),
        ),
        gap(),
        if (s.staffOffers.isEmpty)
          info(
            'No shop offers yet. Enter the agreed terms, voucher quantity and validity to submit one.',
          ),
        ...s.staffOffers.map(
          (o) => Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o['title'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  gap(8),
                  Text(s.shopLabel(o['merchant_id'])),
                  gap(8),
                  Text(o['terms']),
                  gap(8),
                  Text(
                    '${o['approval']} • ${o['stock']} left • ends ${day(o['ends_at'])}',
                  ),
                  if (o['approval'] == 'pending' && admin)
                    Wrap(
                      spacing: 12,
                      children: [
                        TextButton(
                          onPressed: busy ? null : () => approve(o),
                          child: const Text('Review and publish'),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => act(() => s.approveOffer(o, false, '')),
                          child: const Text('Reject'),
                        ),
                      ],
                    ),
                  if (o['approval'] == 'approved')
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: busy ? null : () => stock(o),
                            child: const Text('Edit stock'),
                          ),
                        ),
                        const Text('Open'),
                        Switch(
                          value: o['active'] == true,
                          onChanged: busy
                              ? null
                              : (v) => act(() => s.setOffer(o, o['stock'], v)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
      if (admin && show(ManagementSection.merchants)) ...[
        gap(24),
        const Text(
          'Merchant access requests',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: navy,
          ),
        ),
        gap(),
        if (!s.requests.any((q) => q['status'] == 'pending'))
          const Text('No pending requests.'),
        ...s.requests
            .where((q) => q['status'] == 'pending')
            .map(
              (q) => Card(
                child: ListTile(
                  title: Text(s.shopLabel(q['merchant_id'])),
                  subtitle: Text(q['contact']),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: busy ? null : () => review(q),
                ),
              ),
            ),

        if (s.requests.any((q) => q['status'] != 'pending')) ...[
          gap(24),
          sectionTitle('Reviewed requests'),
          ...s.requests
              .where((q) => q['status'] != 'pending')
              .map(
                (q) => Card(
                  child: ListTile(
                    title: Text(s.shopLabel(q['merchant_id'])),
                    subtitle: Text('${q['status']} • ${q['contact']}'),
                  ),
                ),
              ),
        ],
      ],
      if (admin && show(ManagementSection.malls)) ...[
        gap(24),
        const Text(
          'Mall location setup',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: navy,
          ),
        ),
        gap(),
        ...s.malls.map(
          (m) => Card(
            child: ListTile(
              title: Text(m['name']),
              subtitle: Text(
                '${m['geofence_reviewed'] == true ? 'Reviewed' : 'Boundary review pending'} • ${m['radius_m']} m • ${m['qr_required'] == true ? 'GPS + QR' : 'GPS'}',
              ),
              trailing: const Icon(Icons.settings_outlined),
              onTap: () => Navigator.push(
                c,
                MaterialPageRoute(
                  builder: (_) => MallSettingsPage(store: s, mall: m),
                ),
              ),
            ),
          ),
        ),
        gap(24),
        const Text(
          'Route availability',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: navy,
          ),
        ),
        gap(),
        ...s.routes.map(
          (r) => Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(
                    '${s.mallFor(r['mall_id'])?['name']} • ${r['name']}',
                  ),
                  subtitle: Text(
                    '${r['target_steps']} steps • ${r['active'] == true ? 'Open' : 'Paused'}',
                  ),
                  value: r['active'] == true,
                  onChanged: busy ? null : (v) => act(() => s.setRoute(r, v)),
                ),
                if (r['active'] == true)
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      c,
                      MaterialPageRoute(
                        builder: (_) => StaffQrPage(store: s, route: r),
                      ),
                    ),
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Display rotating check-in QR'),
                  ),
              ],
            ),
          ),
        ),
      ],
      if (admin && show(ManagementSection.reports)) ...[
        gap(24),
        const Text(
          'Route feedback',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: navy,
          ),
        ),
        gap(),
        if (s.reports.isEmpty) const Text('No route issues reported yet.'),
        ...s.reports.map(
          (r) => Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r['category']} • ${r['resolved'] == true ? 'Resolved' : 'Open'}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  gap(8),
                  Text(r['description']),
                  gap(8),
                  Text(
                    '${s.routeFor(r['route_id'])?['name']} • ${day(r['created_at'])}',
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => act(() => s.resolve(r, r['resolved'] != true)),
                    child: Text(
                      r['resolved'] == true ? 'Reopen' : 'Mark resolved',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ]);
  }
}

class OfferEditorPage extends StatefulWidget {
  final LangkahStore store;
  const OfferEditorPage({super.key, required this.store});
  @override
  State<OfferEditorPage> createState() => _OfferEditorPageState();
}

class _OfferEditorPageState extends State<OfferEditorPage> {
  final title = TextEditingController(),
      terms = TextEditingController(),
      stock = TextEditingController(),
      days = TextEditingController(text: '7');
  String? merchant;
  DateTime ends = DateTime.now().add(const Duration(days: 30));
  bool busy = false;
  @override
  void initState() {
    super.initState();
    merchant = widget.store.assignedMerchant;
  }

  @override
  void dispose() {
    for (final c in [title, terms, stock, days]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Create shop offer')),
    body: paddedList([
      heading(
        'An offer residents can use.',
        'Enter the actual offer agreed with the outlet. It will appear to residents after administrator approval.',
      ),
      DropdownButtonFormField<String>(
        initialValue: merchant,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Outlet'),
        items: widget.store.merchants
            .where(
              (m) =>
                  widget.store.role == 'admin' ||
                  m['id'] == widget.store.assignedMerchant,
            )
            .map(
              (m) => DropdownMenuItem<String>(
                value: m['id'],
                child: Text(
                  '${m['name']} • ${widget.store.mallFor(m['mall_id'])?['name']}',
                ),
              ),
            )
            .toList(),
        onChanged: (v) => merchant = v,
      ),
      gap(),
      TextField(
        controller: title,
        maxLength: 100,
        decoration: const InputDecoration(labelText: 'Offer title'),
      ),
      gap(),
      TextField(
        controller: terms,
        maxLength: 2000,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'Terms, minimum spend and exclusions',
        ),
      ),
      gap(),
      TextField(
        controller: stock,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Voucher quantity'),
      ),
      gap(),
      TextField(
        controller: days,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Voucher validity in days (1–90)',
        ),
      ),
      gap(),
      ListTile(
        title: const Text('Campaign last day'),
        subtitle: Text(day(ends.toIso8601String())),
        trailing: const Icon(Icons.calendar_month),
        onTap: () async {
          final d = await showDatePicker(
            context: c,
            initialDate: ends,
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (d != null) {
            setState(() => ends = DateTime(d.year, d.month, d.day, 23, 59, 59));
          }
        },
      ),
      gap(),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                final qty = int.tryParse(stock.text),
                    valid = int.tryParse(days.text);
                if (merchant == null || qty == null || valid == null) {
                  message(c, 'Choose an outlet and enter valid quantities.');
                  return;
                }
                setState(() => busy = true);
                try {
                  await widget.store.submitOffer(
                    merchant!,
                    title.text,
                    terms.text,
                    qty,
                    valid,
                    ends,
                  );
                  if (c.mounted) {
                    Navigator.pop(c);
                    message(c, 'Offer submitted for approval.');
                  }
                } catch (e) {
                  if (c.mounted) message(c, friendlyError(e));
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        child: Text(busy ? 'Saving…' : 'Submit offer'),
      ),
    ]),
  );
}

class MallSettingsPage extends StatefulWidget {
  final LangkahStore store;
  final JsonMap mall;
  const MallSettingsPage({super.key, required this.store, required this.mall});
  @override
  State<MallSettingsPage> createState() => _MallSettingsPageState();
}

class _MallSettingsPageState extends State<MallSettingsPage> {
  late final TextEditingController lat, lon, radius;
  late bool reviewed, qr;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    lat = TextEditingController(text: '${widget.mall['latitude']}');
    lon = TextEditingController(text: '${widget.mall['longitude']}');
    radius = TextEditingController(text: '${widget.mall['radius_m']}');
    reviewed = widget.mall['geofence_reviewed'] == true;
    qr = widget.mall['qr_required'] == true;
  }

  @override
  void dispose() {
    lat.dispose();
    lon.dispose();
    radius.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: Text(widget.mall['name'])),
    body: paddedList([
      heading(
        'Review check-in boundaries.',
        'Initial coordinates come from the official mall’s map link. Check them on site and choose a radius covering the public walking areas.',
      ),
      TextField(
        controller: lat,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: const InputDecoration(labelText: 'Centre latitude'),
      ),
      gap(),
      TextField(
        controller: lon,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: const InputDecoration(labelText: 'Centre longitude'),
      ),
      gap(),
      TextField(
        controller: radius,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Radius in metres (50–500)',
        ),
      ),
      gap(),
      info(
        'GPS is approximate and can include nearby outdoor areas. A reading passes only when its accuracy circle fits within the configured boundary. Test several indoor points before opening missions.',
      ),
      gap(),
      CheckboxListTile(
        value: reviewed,
        onChanged: (v) => setState(() => reviewed = v!),
        title: const Text(
          'I have checked this boundary and the public walking areas on site',
        ),
      ),
      SwitchListTile(
        value: qr,
        onChanged: (v) => setState(() => qr = v),
        title: const Text('Require rotating staff QR'),
        subtitle: const Text(
          'Enable only when staff can display start and finish codes. Existing missions retain their original QR requirement.',
        ),
      ),
      gap(),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                final a = double.tryParse(lat.text),
                    b = double.tryParse(lon.text),
                    r = int.tryParse(radius.text);
                if (a == null || b == null || r == null) {
                  message(c, 'Enter valid coordinates and radius.');
                  return;
                }
                setState(() => busy = true);
                try {
                  await widget.store.configureMall(
                    widget.mall,
                    a,
                    b,
                    r,
                    reviewed,
                    qr,
                  );
                  if (c.mounted) {
                    Navigator.pop(c);
                    message(c, 'Mall configuration saved.');
                  }
                } catch (e) {
                  if (c.mounted) message(c, friendlyError(e));
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        child: Text(busy ? 'Saving…' : 'Save configuration'),
      ),
    ]),
  );
}

class StaffQrPage extends StatefulWidget {
  final LangkahStore store;
  final JsonMap route;
  const StaffQrPage({super.key, required this.store, required this.route});
  @override
  State<StaffQrPage> createState() => _StaffQrPageState();
}

class _StaffQrPageState extends State<StaffQrPage> {
  String kind = 'start';
  JsonMap? token;
  String? error;
  Timer? timer;
  bool fetching = false;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
    timer = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (fetching) return;
    fetching = true;
    final requested = kind;
    try {
      final t = await widget.store.staffToken(widget.route['id'], requested);
      if (mounted && requested == kind) {
        setState(() {
          token = t;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          token = null;
          error = friendlyError(e);
        });
      }
    } finally {
      fetching = false;
    }
  }

  @override
  Widget build(BuildContext c) {
    final valid =
        token != null &&
        DateTime.parse(token!['expires_at']).isAfter(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('Staff check-in QR')),
      body: paddedList([
        heading(
          widget.store.mallFor(widget.route['mall_id'])?['name'] ?? 'Mall',
          '${widget.route['name']} • Show this screen at the staffed checkpoint.',
        ),
        DropdownButtonFormField<String>(
          initialValue: kind,
          decoration: const InputDecoration(labelText: 'Checkpoint'),
          items: const [
            DropdownMenuItem(value: 'start', child: Text('Start')),
            DropdownMenuItem(value: 'finish', child: Text('Finish')),
          ],
          onChanged: (v) {
            setState(() {
              kind = v!;
              token = null;
            });
            unawaited(refresh());
          },
        ),
        gap(24),
        if (error != null) info(error!),
        if (valid)
          Center(
            child: QrImageView(
              data: token!['code'],
              size: 260,
              backgroundColor: Colors.white,
            ),
          ),
        if (valid)
          Center(
            child: SelectableText(
              token!['code'],
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        if (!valid && error == null)
          const Center(child: CircularProgressIndicator()),
        gap(),
        info(
          'Codes expire after 60 seconds. The server checks mission, checkpoint, expiry and the visitor’s GPS. Display at the mall; avoid distributing screenshots.',
        ),
      ]),
    );
  }
}

class RecoveryPage extends StatefulWidget {
  final LangkahStore store;
  final bool recovering;
  const RecoveryPage({super.key, required this.store, this.recovering = false});
  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage> {
  final input = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => WalkingDevice.sandboxEnabled
      ? Scaffold(
          appBar: AppBar(title: const Text('Sandbox account')),
          body: paddedList([
            heading(
              'No password needed.',
              'Sandbox roles are local sample accounts. Use Test controls to switch roles. Test real signup and password recovery in the regular Langkah app.',
            ),
          ]),
        )
      : Scaffold(
          appBar: AppBar(
            title: Text(
              widget.recovering ? 'Set a new password' : 'Recover account',
            ),
          ),
          body: paddedList([
            heading(
              widget.recovering
                  ? 'Choose your new password.'
                  : 'Forgot your password?',
              widget.recovering
                  ? 'Use at least eight characters.'
                  : 'We will send a recovery link. Open it on the phone where Langkah is installed.',
            ),
            TextField(
              controller: input,
              obscureText: widget.recovering,
              keyboardType: widget.recovering
                  ? TextInputType.visiblePassword
                  : TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: widget.recovering ? 'New password' : 'Account email',
              ),
            ),
            gap(),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (widget.recovering && input.text.length < 8) {
                        message(c, 'Use at least eight characters.');
                        return;
                      }
                      setState(() => busy = true);
                      try {
                        if (widget.recovering) {
                          await widget.store.client!.auth.updateUser(
                            UserAttributes(password: input.text),
                          );
                        } else {
                          await widget.store.client!.auth.resetPasswordForEmail(
                            input.text.trim(),
                            redirectTo: 'langkah://auth/callback',
                          );
                        }
                        if (c.mounted) {
                          Navigator.pop(c);
                          message(
                            c,
                            widget.recovering
                                ? 'Password updated.'
                                : 'If that account exists, check its inbox for a recovery link.',
                          );
                        }
                      } catch (e) {
                        if (c.mounted) message(c, friendlyError(e));
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: Text(
                busy
                    ? 'Saving…'
                    : widget.recovering
                    ? 'Update password'
                    : 'Send recovery link',
              ),
            ),
          ]),
        );
}
