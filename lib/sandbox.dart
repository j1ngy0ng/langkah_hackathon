import 'package:flutter/material.dart';
import 'device.dart';
import 'main.dart' show AppRoot;
import 'sandbox_store.dart';
import 'store.dart' show friendlyError;
import 'ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!WalkingDevice.sandboxEnabled) {
    throw StateError('Use build-sandbox.ps1 to build the isolated sandbox.');
  }
  runApp(SandboxApp(store: SandboxStore()));
}

class SandboxApp extends StatefulWidget {
  final SandboxStore store;
  const SandboxApp({super.key, required this.store});
  @override
  State<SandboxApp> createState() => _SandboxAppState();
}

class _SandboxAppState extends State<SandboxApp> {
  GlobalKey<NavigatorState> navigation = GlobalKey<NavigatorState>();
  String workspace = '';
  SandboxStore get store => widget.store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final nextWorkspace = '${store.role}-${store.generation}';
      if (workspace != nextWorkspace) {
        workspace = nextWorkspace;
        navigation = GlobalKey<NavigatorState>();
      }
      return MaterialApp(
        key: ValueKey(workspace),
        navigatorKey: navigation,
        title: 'Langkah Sandbox',
        debugShowCheckedModeBanner: false,
        theme: langkahTheme(),
        home: AppRoot(store: store),
        builder: (context, child) => Column(
          children: [
            SizedBox(
              height: 64 + MediaQuery.paddingOf(context).top,
              child: Material(
                color: const Color(0xFFFFE4AD),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'SANDBOX\n${store.role} · TEST ONLY',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: controls,
                          icon: const Icon(Icons.tune, size: 18),
                          label: const Text('Test controls'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => MediaQuery(
                  data: MediaQuery.of(context)
                      .removePadding(removeTop: true)
                      .copyWith(
                        size: Size(constraints.maxWidth, constraints.maxHeight),
                      ),
                  child: child!,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  Future<void> controls() async {
    String? error;
    await showModalBottomSheet<void>(
      context: navigation.currentState!.overlay!.context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setPanelState) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: ListenableBuilder(
                listenable: store,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Test from anywhere',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Offline sample data. No login or Supabase connection. Changes reset when this app restarts. No sample voucher is valid at a shop.',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final role in ['resident', 'admin', 'merchant'])
                          ChoiceChip(
                            label: Text(
                              role[0].toUpperCase() + role.substring(1),
                            ),
                            selected: store.role == role,
                            onSelected: (_) {
                              Navigator.pop(context);
                              store.switchRole(role);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: store.assignedMerchant,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Merchant outlet to test',
                      ),
                      items: store.merchants
                          .map(
                            (m) => DropdownMenuItem(
                              value: m['id'] as String,
                              child: Text(
                                '${m['name']} • ${store.mallFor(m['mall_id'])!['name']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          store.switchRole(store.role, merchant: v);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: store.locationState,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Simulated location',
                      ),
                      items: [
                        for (final label in [
                          'Inside mall',
                          'Outside mall',
                          'Mock GPS',
                          'Weak accuracy',
                          'Stale GPS',
                          'No GPS fix',
                          'Location off',
                        ])
                          DropdownMenuItem(
                            value: label,
                            child: Text(label, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) store.setLocationState(v);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Mission: ${store.session?['steps'] ?? 0} steps • ${store.session?['status'] ?? 'not started'}',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Start a resident mission, tap Resume step tracking, then add steps here. Close this panel to choose a reward.',
                    ),
                    const SizedBox(height: 12),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final count in [100, 500])
                          FilledButton(
                            onPressed: () async {
                              setPanelState(() => error = null);
                              try {
                                await store.addSteps(count);
                              } catch (e) {
                                if (context.mounted) {
                                  setPanelState(() => error = friendlyError(e));
                                }
                              }
                            },
                            child: Text('+$count steps'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        try {
                          store.expireLatestVoucher();
                        } catch (e) {
                          setPanelState(() => error = friendlyError(e));
                        }
                      },
                      child: const Text('Expire latest sample voucher'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        store.reset();
                      },
                      child: const Text('Reset sample data'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close controls'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
