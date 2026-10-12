import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langkah_hackathon/main.dart';
import 'package:langkah_hackathon/store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Fixture extends LangkahStore {
  @override
  bool get signedIn => true;
  @override
  Future<void> refresh() async {}
  Fixture() {
    roleReady = true;
    malls = [
      {
        'id': 'elmina',
        'name': 'Elmina Lakeside Mall',
        'area': 'City of Elmina',
        'address': 'Shah Alam',
        'qr_required': false,
        'geofence_reviewed': false,
      },
      {
        'id': 'kl-east',
        'name': 'KL East Mall',
        'area': 'Kuala Lumpur',
        'address': 'KL East',
        'qr_required': false,
        'geofence_reviewed': false,
      },
      {
        'id': 'klgcc',
        'name': 'KLGCC Mall',
        'area': 'Bukit Kiara',
        'address': 'Kuala Lumpur',
        'qr_required': false,
        'geofence_reviewed': false,
      },
    ];
    merchants = [
      {
        'id': 'elmina-zus',
        'mall_id': 'elmina',
        'name': 'ZUS Coffee',
        'lot': 'GF-95 & 96',
      },
      {
        'id': 'kleast-zus',
        'mall_id': 'kl-east',
        'name': 'ZUS Coffee',
        'lot': 'G2K-03A',
      },
    ];
    routes = [
      {
        'id': 'elmina-500',
        'mall_id': 'elmina',
        'name': 'A little mall walk',
        'target_steps': 500,
        'minutes': 10,
        'description': 'Walk at your pace.',
        'accessibility': 'Use public walkways.',
        'active': false,
      },
    ];
  }
}

void main() {
  test(
    'Device failures show actionable messages without platform internals',
    () {
      const message =
          'Mock location detected. Stop your location-changing app.';
      expect(
        friendlyError(
          PlatformException(code: 'MOCK_LOCATION', message: message),
        ),
        message,
      );
      expect(
        friendlyError(
          PlatformException(
            code: 'LOCATION_TIMEOUT',
            message: 'Could not get a fresh location.',
          ),
        ),
        'Could not get a fresh location.',
      );
      expect(
        friendlyError(PlatformException(code: 'LOCATION')),
        'Your phone could not complete this check. Try again.',
      );
    },
  );
  test('Sensor baseline, pause and reset never award historical steps', () {
    final c = StepAccumulator();
    c.addReading(6000);
    c.addReading(6020);
    expect(c.steps, 20);
    c.resume();
    c.addReading(6500);
    c.addReading(6505);
    expect(c.steps, 25);
    c.addReading(3);
    c.addReading(8);
    c.addReading(-1);
    expect(c.steps, 30);
  });
  test(
    'Rewards are scoped to mission mall and require approval, stock and a current campaign',
    () {
      final s = Fixture();
      final end = DateTime.now().add(const Duration(days: 1)).toIso8601String();
      s.offers = [
        {
          'id': 'a',
          'merchant_id': 'elmina-zus',
          'approval': 'approved',
          'active': true,
          'stock': 2,
          'ends_at': end,
        },
        {
          'id': 'b',
          'merchant_id': 'kleast-zus',
          'approval': 'approved',
          'active': true,
          'stock': 2,
          'ends_at': end,
        },
        {
          'id': 'c',
          'merchant_id': 'elmina-zus',
          'approval': 'pending',
          'active': true,
          'stock': 2,
          'ends_at': end,
        },
        {
          'id': 'd',
          'merchant_id': 'elmina-zus',
          'approval': 'approved',
          'active': true,
          'stock': 0,
          'ends_at': end,
        },
        {
          'id': 'e',
          'merchant_id': 'elmina-zus',
          'approval': 'approved',
          'active': true,
          'stock': 2,
          'ends_at': '2020-01-01T00:00:00Z',
        },
      ];
      expect(s.availableOffers.map((o) => o['id']), ['a']);
      s.selectMall('kl-east');
      expect(s.availableOffers.map((o) => o['id']), ['b']);
      s.session = {'route_id': 'elmina-500'};
      expect(s.availableOffers.map((o) => o['id']), ['a']);
    },
  );
  testWidgets(
    'Mall selection changes directory and has no simulated-walk controls',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = Fixture();
      await tester.pumpWidget(LangkahApp(store: s));
      await tester.pumpAndSettle();
      expect(find.text('Elmina Lakeside Mall'), findsWidgets);
      expect(find.text('Explore the demo'), findsNothing);
      expect(find.text('Simulate 100 steps'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('KL East Mall').last);
      await tester.pumpAndSettle();
      expect(s.selectedMall, 'kl-east');
      await tester.scrollUntilVisible(
        find.text('Lot G2K-03A'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(ExplorePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Lot G2K-03A'), findsOneWidget);
      expect(find.text('Lot GF-95 & 96'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Unconfigured boundary keeps mission start disabled', (
    tester,
  ) async {
    final s = Fixture();
    s.routes.first['active'] = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExplorePage(store: s, onMission: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start this mission'),
    );
    expect(button.onPressed, isNull);
  });
  testWidgets('Welcome supports narrow screen and large text', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: WelcomePage(store: LangkahStore()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Administrator receives live setup and offer controls', (
    tester,
  ) async {
    final s = Fixture()..role = 'admin';
    await tester.pumpWidget(LangkahApp(store: s));
    await tester.pumpAndSettle();
    expect(find.text('Township dashboard'), findsOneWidget);
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.destinations.map((d) => (d as NavigationDestination).label), [
      'Dashboard',
      'Malls',
      'Merchants',
      'Rewards',
      'Reports',
    ]);
    expect(find.byType(ExplorePage, skipOffstage: false), findsNothing);
    expect(find.byType(MissionPage, skipOffstage: false), findsNothing);
    expect(find.byType(WalletPage, skipOffstage: false), findsNothing);
    expect(find.byType(ProfilePage, skipOffstage: false), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Pending offers'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey(ManagementSection.overview)),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Pending offers'));
    await tester.pumpAndSettle();
    expect(find.text('Shop rewards'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Create an offer for approval'),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey(ManagementSection.rewards)),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Create an offer for approval'), findsOneWidget);
    await tester.tap(find.text('Malls').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Mall location setup'),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey(ManagementSection.malls)),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Mall location setup'), findsOneWidget);
    await tester.tap(find.text('Merchants').last);
    await tester.pumpAndSettle();
    expect(find.text('Merchant access requests'), findsOneWidget);
    await tester.tap(find.text('Reports').last);
    await tester.pumpAndSettle();
    expect(find.text('Community reports'), findsOneWidget);
    await tester.tap(find.byTooltip('Admin account'));
    await tester.pumpAndSettle();
    expect(find.text('Your account'), findsOneWidget);
    expect(find.text('Active days'), findsNothing);
    expect(find.text('Recent missions'), findsNothing);
    expect(find.text('Sign out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Merchant workspace contains only assigned offers, redemption and account',
    (tester) async {
      final s = Fixture()
        ..role = 'merchant'
        ..assignedMerchant = 'elmina-zus';
      final expiry = DateTime.now()
          .add(const Duration(days: 7))
          .toIso8601String();
      s.offers = [
        for (final shop in ['elmina-zus', 'kleast-zus'])
          {
            'id': shop,
            'merchant_id': shop,
            'title': shop == 'elmina-zus'
                ? 'Assigned outlet offer'
                : 'Other outlet offer',
            'terms': 'Merchant-supplied terms.',
            'approval': 'approved',
            'stock': 10,
            'active': true,
            'ends_at': expiry,
          },
      ];
      await tester.pumpWidget(LangkahApp(store: s));
      await tester.pumpAndSettle();
      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.destinations.map((d) => (d as NavigationDestination).label), [
        'Offers',
        'Redeem',
      ]);
      expect(find.text('Your shop offers'), findsOneWidget);
      expect(find.text('Assigned outlet offer'), findsOneWidget);
      expect(
        find.text('Other outlet offer', skipOffstage: false),
        findsNothing,
      );
      expect(find.text('Create an offer for approval'), findsOneWidget);
      expect(find.text('Scan voucher'), findsNothing);
      for (final page in [ExplorePage, MissionPage, WalletPage, ProfilePage]) {
        expect(find.byType(page, skipOffstage: false), findsNothing);
      }
      expect(
        find.text('Mall location setup', skipOffstage: false),
        findsNothing,
      );
      expect(
        find.text('Review and publish', skipOffstage: false),
        findsNothing,
      );
      await tester.tap(find.text('Redeem').last);
      await tester.pumpAndSettle();
      expect(find.text('Voucher redemption'), findsOneWidget);
      expect(find.text('Scan voucher'), findsOneWidget);
      expect(find.text('Validate and redeem'), findsOneWidget);
      expect(find.text('Assigned outlet offer'), findsNothing);
      await tester.tap(find.byTooltip('Merchant account'));
      await tester.pumpAndSettle();
      expect(find.text('Merchant account'), findsOneWidget);
      expect(find.text('Outlet representative'), findsOneWidget);
      expect(find.text('Elmina Lakeside Mall'), findsOneWidget);
      expect(find.text('Active days'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Sign out'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(StaffAccountPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Sign out'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Workspace waits for verified role and resets after a role change',
    (tester) async {
      final s = Fixture()..roleReady = false;
      await tester.pumpWidget(LangkahApp(store: s));
      await tester.pump();
      expect(find.text('Preparing your workspace'), findsOneWidget);
      expect(find.byType(MissionPage, skipOffstage: false), findsNothing);
      s.roleReady = true;
      s.selectMall('elmina');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wallet').last);
      await tester.pumpAndSettle();
      s.role = 'admin';
      s.selectMall('elmina');
      await tester.pumpAndSettle();
      expect(find.text('Township dashboard'), findsOneWidget);
      expect(find.byType(WalletPage, skipOffstage: false), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await tester.tap(find.text('Reports').last);
      await tester.pumpAndSettle();
      s.role = 'merchant';
      s.assignedMerchant = 'elmina-zus';
      s.selectMall('elmina');
      await tester.pumpAndSettle();
      expect(find.text('Your shop offers'), findsOneWidget);
      expect(
        find.text('Township dashboard', skipOffstage: false),
        findsNothing,
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Small-screen account form preserves input and reveals password',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = (await tester.runAsync(
        () async => SupabaseClient(
          'https://example.supabase.co',
          'test-only-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      ))!;
      await tester.pumpWidget(LangkahApp(store: LangkahStore(client: client)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'walker@example.com',
      );
      await tester.enterText(find.byType(TextField).last, 'a-password');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).last).obscureText,
        isFalse,
      );
      await tester.ensureVisible(
        find.widgetWithText(TextButton, 'Create account'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(3));
      expect(find.text('walker@example.com'), findsOneWidget);
      expect(find.text('a-password'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => client.dispose());
    },
  );

  testWidgets('Empty mission and wallet lead back to real mission selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = Fixture();
    await tester.pumpWidget(LangkahApp(store: s));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mission').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Find a walking mission'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find a walking mission'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your mission').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Wallet').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Explore walking missions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explore walking missions'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your mission').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
