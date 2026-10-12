import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langkah_hackathon/device.dart';
import 'package:langkah_hackathon/sandbox.dart';
import 'package:langkah_hackathon/sandbox_store.dart';

void main() {
  if (!WalkingDevice.sandboxEnabled) {
    test('Production build refuses to initialise sandbox data', () {
      expect(SandboxStore.new, throwsStateError);
    });
    return;
  }
  test(
    'Offline mission, choice, stock, outlet scope and single-use redemption',
    () async {
      final s = SandboxStore();
      expect(s.client, isNull);
      final route = s.mallRoutes.first;
      await s.start(route, location: s.simulatedLocation());
      expect(s.availableOffers.length, 3);
      await expectLater(
        s.claim(s.availableOffers.first['id']),
        throwsStateError,
      );
      await s.progress(500, s.simulatedLocation());
      final offer = s.availableOffers.first;
      final voucher = await s.claim(offer['id']);
      expect(offer['stock'], 9);
      expect(s.session, isNull);
      expect(s.myVouchers.length, 1);
      expect(voucher['code'], startsWith('TEST-'));
      expect(voucher['terms_snapshot'], contains('No monetary value'));
      s.switchRole('merchant', merchant: 'kleast-zus');
      await expectLater(s.redeem(voucher['code']), throwsStateError);
      s.switchRole('merchant', merchant: 'elmina-zus');
      await s.redeem(voucher['code']);
      await expectLater(s.redeem(voucher['code']), throwsStateError);
      expect(s.status(voucher), 'Redeemed');
      s.dispose();
    },
  );
  test(
    'Location failures, route review, reports and merchant offer approval',
    () async {
      final s = SandboxStore();
      for (final failure in ['Outside mall', 'Weak accuracy', 'Stale GPS']) {
        s.setLocationState(failure);
        await expectLater(
          s.start(s.mallRoutes.first, location: s.simulatedLocation()),
          throwsStateError,
        );
      }
      for (final failure in ['Mock GPS', 'No GPS fix', 'Location off']) {
        s.setLocationState(failure);
        expect(s.simulatedLocation, throwsA(isA<PlatformException>()));
      }
      s.setLocationState('Inside mall');
      await s.report('elmina-500', 'Obstruction', 'Test blocked walkway');
      s.switchRole('admin');
      await s.resolve(s.reports.first, true);
      expect(s.reports.first['resolved'], true);
      final mall = s.malls.first;
      await s.configureMall(
        mall,
        mall['latitude'],
        mall['longitude'],
        200,
        false,
        false,
      );
      await expectLater(s.setRoute(s.mallRoutes.first, true), throwsStateError);
      s.switchRole('merchant');
      await s.submitOffer(
        'elmina-zus',
        'Trial offer',
        'Testing only',
        2,
        7,
        DateTime.now().add(const Duration(days: 2)),
      );
      final offer = s.offers.first;
      expect(offer['approval'], 'pending');
      await expectLater(s.setOffer(offer, 2, true), throwsStateError);
      s.switchRole('admin');
      await s.approveOffer(offer, true, 'test approval');
      expect(offer['active'], true);
      s.reset();
      expect(s.vouchers, isEmpty);
      expect(s.reports, isEmpty);
      expect(s.offers.length, 9);
      s.dispose();
    },
  );
  test(
    'Sample daily cap, expired vouchers and optional staff checkpoints',
    () async {
      final s = SandboxStore();
      for (var i = 0; i < 2; i++) {
        await s.start(s.mallRoutes.first, location: s.simulatedLocation());
        await s.progress(500, s.simulatedLocation());
        await s.claim(s.availableOffers.first['id']);
      }
      await s.start(s.mallRoutes.first, location: s.simulatedLocation());
      await s.progress(500, s.simulatedLocation());
      await expectLater(
        s.claim(s.availableOffers.first['id']),
        throwsStateError,
      );
      s.expireLatestVoucher();
      s.switchRole('merchant');
      await expectLater(s.redeem(s.vouchers.first['code']), throwsStateError);
      s.reset();
      s.switchRole('admin');
      s.malls.first['qr_required'] = true;
      final start = await s.staffToken('elmina-500', 'start');
      final finish = await s.staffToken('elmina-500', 'finish');
      s.switchRole('resident');
      await expectLater(
        s.start(
          s.mallRoutes.first,
          location: s.simulatedLocation(),
          code: finish['code'],
        ),
        throwsStateError,
      );
      await s.start(
        s.mallRoutes.first,
        location: s.simulatedLocation(),
        code: start['code'],
      );
      await s.progress(500, s.simulatedLocation());
      expect(s.session!['status'], 'walking');
      await s.checkpoint(finish['code'], s.simulatedLocation());
      expect(s.session!['status'], 'eligible');
      s.dispose();
    },
  );
  testWidgets('Shared UI starts, simulates steps and offers reward selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final s = SandboxStore();
    await tester.pumpWidget(SandboxApp(store: s));
    await tester.pumpAndSettle();
    expect(find.textContaining('SANDBOX'), findsOneWidget);
    final start = find.text('Start this mission');
    await tester.scrollUntilVisible(
      start,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(start.first);
    await tester.pumpAndSettle();
    expect(s.session!['steps'], 0);
    final resume = find.text('Resume step tracking');
    await tester.scrollUntilVisible(
      resume,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(resume);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test controls'));
    await tester.pumpAndSettle();
    final add = find.text('+500 steps');
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(s.session!['status'], 'eligible');
    expect(s.session!['steps'], 500);
    await tester.ensureVisible(find.text('Close controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close controls'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Choose my reward'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose my reward'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('A reward, well earned.'), findsOneWidget);
    expect(s.availableOffers.length, 3);
    expect(find.text('TEST ONLY • sample reward'), findsWidgets);
    final choose = find.text('Choose this reward');
    await tester.scrollUntilVisible(
      choose,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(choose.first);
    await tester.pumpAndSettle();
    expect(s.vouchers.length, 1);
    expect(find.text(s.vouchers.first['code']), findsOneWidget);
    await tester.tap(find.text('Test controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Merchant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redeem'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), s.vouchers.first['code']);
    final redeem = find.text('Validate and redeem');
    await tester.ensureVisible(redeem);
    await tester.pumpAndSettle();
    await tester.tap(redeem);
    await tester.pumpAndSettle();
    expect(s.vouchers.first['redeemed_at'], isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  testWidgets(
    'Sandbox controls work on narrow enlarged-text screens and switch roles',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = SandboxStore();
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: SandboxApp(store: s),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test controls'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Merchant'));
      await tester.pumpAndSettle();
      expect(find.text('Your shop offers'), findsOneWidget);
      expect(find.text('Explore'), findsNothing);
      expect(find.text('Redeem'), findsOneWidget);
      await tester.tap(find.text('Test controls'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Admin'));
      await tester.pumpAndSettle();
      expect(find.text('Township dashboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    },
  );
}
