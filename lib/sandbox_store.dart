import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'device.dart';
import 'store.dart';

// Imported only by the sandbox entry point. No Supabase client or credentials.
class SandboxStore extends LangkahStore {
  String locationState = 'Inside mall';
  int _serial = 0, _sensorTotal = 10000, generation = 0;
  bool _addingSteps = false;
  final _steps = StreamController<int>.broadcast();
  final Map<String, JsonMap> _tokens = {};
  SandboxStore() {
    if (!WalkingDevice.sandboxEnabled) {
      throw StateError(
        'Build the separate Langkah Sandbox APK to use simulated inputs.',
      );
    }
    reset();
    WalkingDevice.sandboxLocation = simulatedLocation;
    WalkingDevice.sandboxSteps = Stream<int>.multi((events) {
      events.add(_sensorTotal);
      final sub = _steps.stream.listen(events.add);
      events.onCancel = sub.cancel;
    }, isBroadcast: true);
  }
  @override
  bool get signedIn => true;
  @override
  String get userId => 'sandbox-resident';
  @override
  String get email => '$role@sandbox.invalid';
  @override
  String get name => 'Sandbox ${role[0].toUpperCase()}${role.substring(1)}';
  String _id(String kind) => 'TEST-${kind.toUpperCase()}-${++_serial}';
  String get _now => DateTime.now().toUtc().toIso8601String();

  void reset() {
    generation++;
    role = 'resident';
    roleReady = true;
    selectedMall = 'elmina';
    assignedMerchant = 'elmina-zus';
    session = null;
    locationState = 'Inside mall';
    vouchers = [];
    history = [];
    reports = [];
    requests = [];
    offers = [];
    _tokens.clear();
    malls =
        [
              {
                'id': 'elmina',
                'name': 'Elmina Lakeside Mall',
                'area': 'City of Elmina',
                'latitude': 3.223033,
                'longitude': 101.4370898,
                'address': 'No. 5, Persiaran Garcinia, Elmina West, Shah Alam',
                'source_url':
                    'https://www.simedarbyproperty.com/malls/elmina-lake-side-mall/',
              },
              {
                'id': 'kl-east',
                'name': 'KL East Mall',
                'area': 'KL East, Kuala Lumpur',
                'latitude': 3.2247781,
                'longitude': 101.7304658,
                'address': '823, Jalan Lingkaran Tengah 2, KL Timur',
                'source_url':
                    'https://www.simedarbyproperty.com/malls/kleast-mall/',
              },
              {
                'id': 'klgcc',
                'name': 'KLGCC Mall',
                'area': 'Bukit Kiara, Kuala Lumpur',
                'latitude': 3.1376273,
                'longitude': 101.6485627,
                'address': 'Jalan Bukit Kiara 1, Bukit Kiara',
                'source_url':
                    'https://www.simedarbyproperty.com/malls/klgcc-mall/',
              },
            ]
            .map<JsonMap>(
              (m) => {
                ...m,
                'radius_m': 200,
                'geofence_reviewed': true,
                'qr_required': false,
                'verified_at': '2026-10-11',
              },
            )
            .toList();
    merchants = [
      {
        'id': 'elmina-zus',
        'mall_id': 'elmina',
        'name': 'ZUS Coffee',
        'lot': 'GF-95 & 96',
      },
      {
        'id': 'elmina-scoop',
        'mall_id': 'elmina',
        'name': 'Inside Scoop',
        'lot': 'GF-13A',
      },
      {
        'id': 'elmina-decathlon',
        'mall_id': 'elmina',
        'name': 'Decathlon',
        'lot': 'GF-97',
      },
      {
        'id': 'kleast-zus',
        'mall_id': 'kl-east',
        'name': 'ZUS Coffee',
        'lot': 'G2K-03A',
      },
      {
        'id': 'kleast-scoop',
        'mall_id': 'kl-east',
        'name': 'Inside Scoop',
        'lot': 'G1K-01',
      },
      {
        'id': 'kleast-decathlon',
        'mall_id': 'kl-east',
        'name': 'Decathlon',
        'lot': 'G2-17, G2-17A, G2-18, G2-19 & G2-20',
      },
      {
        'id': 'klgcc-huckleberry',
        'mall_id': 'klgcc',
        'name': 'Huckleberry',
        'lot': 'GF-13',
      },
      {
        'id': 'klgcc-matcha',
        'mall_id': 'klgcc',
        'name': 'Oh Cha Matcha',
        'lot': 'GFK-03',
      },
      {
        'id': 'klgcc-jaya',
        'mall_id': 'klgcc',
        'name': 'Jaya Grocer',
        'lot': 'GF-07',
      },
    ];
    routes = [
      for (final m in malls)
        for (final target in [500, 1000])
          {
            'id': '${m['id']}-$target',
            'mall_id': m['id'],
            'name': target == 500 ? 'A little mall walk' : 'Make time to move',
            'target_steps': target,
            'minutes': target == 500 ? 10 : 20,
            'description':
                'Sandbox mission. Simulate steps from Test controls.',
            'accessibility':
                'Sample route only; no on-site accessibility review.',
            'active': true,
          },
    ];
    merchants = merchants
        .map<JsonMap>(
          (m) => {
            ...m,
            'source_url': mallFor(m['mall_id'])!['source_url'],
            'verified_at': '2026-10-11',
          },
        )
        .toList();
    for (final merchant in merchants) {
      offers.add({
        'id': _id('offer'),
        'merchant_id': merchant['id'],
        'title': 'TEST ONLY • sample reward',
        'terms':
            'Sample voucher for app testing. No monetary value. Not an offer from ${merchant['name']}; shops will not accept it.',
        'stock': 10,
        'active': true,
        'approval': 'approved',
        'valid_days': 7,
        'ends_at': DateTime.now()
            .add(const Duration(days: 30))
            .toUtc()
            .toIso8601String(),
      });
    }
    notifyListeners();
  }

  void switchRole(String value, {String? merchant}) {
    role = value;
    assignedMerchant = merchant ?? assignedMerchant;
    notifyListeners();
  }

  void setLocationState(String value) {
    locationState = value;
    notifyListeners();
  }

  JsonMap simulatedLocation() {
    if (locationState == 'Mock GPS') {
      throw PlatformException(
        code: 'MOCK_LOCATION',
        message:
            'Mock location detected. Choose Inside mall in Test controls to continue.',
      );
    }
    if (locationState == 'No GPS fix') {
      throw PlatformException(
        code: 'LOCATION_TIMEOUT',
        message:
            'Could not get a fresh location. Choose Inside mall in Test controls to retry.',
      );
    }
    if (locationState == 'Location off') {
      throw PlatformException(
        code: 'LOCATION_OFF',
        message: 'Enable location. Choose Inside mall in Test controls.',
      );
    }
    final mall = mallFor(
      routeFor(session?['route_id'])?['mall_id'] ?? selectedMall,
    )!;
    return {
      'latitude':
          (mall['latitude'] as num).toDouble() +
          (locationState == 'Outside mall' ? .02 : 0),
      'longitude': mall['longitude'],
      'accuracy': locationState == 'Weak accuracy' ? 100.0 : 10.0,
      'age_ms': locationState == 'Stale GPS' ? 20000 : 0,
    };
  }

  void _checkLocation(String mallId, JsonMap location) {
    final mall = mallFor(mallId)!;
    if (mall['geofence_reviewed'] != true) {
      throw StateError('Mall location boundary awaits administrator review.');
    }
    if ((location['age_ms'] as num) > 15000) {
      throw StateError('Location is too old. Get a fresh reading.');
    }
    final accuracy = (location['accuracy'] as num).toDouble();
    if (!accuracy.isFinite || accuracy < 0 || accuracy > 75) {
      throw StateError('Your location is not accurate enough yet.');
    }
    final north =
        ((location['latitude'] as num) - (mall['latitude'] as num)) * 111320;
    final east =
        ((location['longitude'] as num) - (mall['longitude'] as num)) *
        111320 *
        math.cos((mall['latitude'] as num) * math.pi / 180);
    if (math.sqrt(north * north + east * east) + accuracy >
        (mall['radius_m'] as num)) {
      throw StateError(
        'Location is outside or too close to the mall boundary.',
      );
    }
  }

  void _requireAdmin() {
    if (role != 'admin') throw StateError('Administrator access required.');
  }

  void _requireShop(String merchant) {
    if (role != 'admin' &&
        (role != 'merchant' || assignedMerchant != merchant)) {
      throw StateError('This voucher or offer belongs to another outlet.');
    }
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> signOut() async {
    switchRole('resident');
  }

  @override
  Future<JsonMap> start(
    JsonMap route, {
    required JsonMap location,
    String? code,
  }) async {
    if (role != 'resident') {
      throw StateError('Switch to Resident to start a walk.');
    }
    _checkLocation(route['mall_id'], location);
    if (route['active'] != true) throw StateError('This mission is paused.');
    if (session != null) {
      if (session!['route_id'] != route['id']) {
        throw StateError('Finish or cancel your current mission first.');
      }
      return session!;
    }
    final qr = mallFor(route['mall_id'])!['qr_required'] == true;
    if (qr) _useToken(code, route['id'], 'start');
    session = {
      'id': _id('mission'),
      'user_id': userId,
      'route_id': route['id'],
      'steps': 0,
      'status': 'walking',
      'qr_required': qr,
      'checkpoint_count': qr ? 1 : 0,
      'started_at': _now,
    };
    history.insert(0, session!);
    notifyListeners();
    return session!;
  }

  @override
  Future<void> progress(int steps, JsonMap location) async {
    if (session == null) throw StateError('Start a mission first.');
    final route = routeFor(session!['route_id'])!;
    _checkLocation(route['mall_id'], location);
    if (route['active'] != true) throw StateError('This mission is paused.');
    if (steps < (session!['steps'] as int)) {
      throw StateError('Steps cannot go backwards.');
    }
    session!['steps'] = steps;
    session!['status'] =
        steps >= (route['target_steps'] as int) &&
            (session!['qr_required'] != true ||
                session!['checkpoint_count'] == 2)
        ? 'eligible'
        : 'walking';
    notifyListeners();
  }

  Future<void> addSteps(int count) async {
    if (role != 'resident' || session == null || !_steps.hasListener) {
      throw StateError('Start a mission and tap Resume step tracking first.');
    }
    final location = simulatedLocation();
    _checkLocation(routeFor(session!['route_id'])!['mall_id'], location);
    if (_addingSteps) return;
    _addingSteps = true;
    final expectedSteps = (session!['steps'] as int) + count;
    final missionId = session!['id'];
    _sensorTotal += count;
    _steps.add(_sensorTotal);
    try {
      await Future<void>.delayed(Duration.zero);
      if (session?['id'] == missionId) await progress(expectedSteps, location);
    } finally {
      _addingSteps = false;
    }
  }

  @override
  Future<void> checkpoint(String code, JsonMap location) async {
    if (session == null ||
        session!['qr_required'] != true ||
        session!['checkpoint_count'] != 1) {
      throw StateError('No pending finish checkpoint.');
    }
    final route = routeFor(session!['route_id'])!;
    _checkLocation(route['mall_id'], location);
    if ((session!['steps'] as int) < (route['target_steps'] as int)) {
      throw StateError('Reach your step goal first.');
    }
    _useToken(code, route['id'], 'finish');
    session!['checkpoint_count'] = 2;
    session!['status'] = 'eligible';
    notifyListeners();
  }

  @override
  Future<JsonMap> claim(String offerId) async {
    final previous = vouchers
        .where((v) => v['session_id'] == session?['id'])
        .firstOrNull;
    if (previous != null) return previous;
    if (role != 'resident' || session?['status'] != 'eligible') {
      throw StateError('Complete the mission first.');
    }
    final offer = availableOffers.where((o) => o['id'] == offerId).firstOrNull;
    if (offer == null) throw StateError('This reward is unavailable.');
    if (routeFor(session!['route_id'])!['active'] != true) {
      throw StateError('This mission is paused.');
    }
    if (vouchers
            .where(
              (v) =>
                  v['user_id'] == userId &&
                  _malaysiaDay(v['issued_at']) == _malaysiaDay(_now),
            )
            .length >=
        2) {
      throw StateError(
        'Two rewards per day. Use Reset sample data to start a new test.',
      );
    }
    final voucher = {
      'id': _id('voucher'),
      'code': _id('code'),
      'user_id': userId,
      'session_id': session!['id'],
      'offer_id': offerId,
      'merchant_id': offer['merchant_id'],
      'title_snapshot': offer['title'],
      'terms_snapshot': offer['terms'],
      'merchant_snapshot': shopLabel(offer['merchant_id']),
      'issued_at': _now,
      'expires_at': DateTime.now()
          .add(Duration(days: offer['valid_days'] as int))
          .toUtc()
          .toIso8601String(),
      'redeemed_at': null,
    };
    offer['stock'] = (offer['stock'] as int) - 1;
    session!['status'] = 'claimed';
    vouchers.insert(0, voucher);
    session = null;
    notifyListeners();
    return voucher;
  }

  String _malaysiaDay(String timestamp) => DateTime.parse(
    timestamp,
  ).toUtc().add(const Duration(hours: 8)).toIso8601String().substring(0, 10);
  @override
  Future<void> cancel() async {
    session?['status'] = 'cancelled';
    session = null;
    notifyListeners();
  }

  @override
  Future<JsonMap> redeem(String code) async {
    final voucher = vouchers
        .where((v) => v['code'] == code.trim().toUpperCase())
        .firstOrNull;
    if (voucher == null) throw StateError('Unknown sandbox voucher code.');
    _requireShop(voucher['merchant_id']);
    if (status(voucher) != 'Available') {
      throw StateError('Voucher is already redeemed or expired.');
    }
    voucher['redeemed_at'] = _now;
    notifyListeners();
    return voucher;
  }

  @override
  Future<void> refreshVoucher(String id) async {
    notifyListeners();
  }

  @override
  Future<void> report(
    String routeId,
    String category,
    String description,
  ) async {
    if (description.trim().length < 5) {
      throw StateError('Describe the issue in at least five characters.');
    }
    reports.insert(0, {
      'id': _id('report'),
      'user_id': userId,
      'route_id': routeId,
      'category': category,
      'description': description.trim(),
      'created_at': _now,
      'resolved': false,
    });
    notifyListeners();
  }

  @override
  Future<void> setOffer(JsonMap offer, int stock, bool active) async {
    _requireShop(offer['merchant_id']);
    if (stock < 0) throw StateError('Stock cannot be negative.');
    if (active && offer['approval'] != 'approved') {
      throw StateError('The offer must be approved first.');
    }
    offer['stock'] = stock;
    offer['active'] = active;
    notifyListeners();
  }

  @override
  Future<void> resolve(JsonMap report, bool value) async {
    _requireAdmin();
    report['resolved'] = value;
    notifyListeners();
  }

  @override
  Future<void> setRoute(JsonMap route, bool value) async {
    _requireAdmin();
    if (value && mallFor(route['mall_id'])!['geofence_reviewed'] != true) {
      throw StateError('Review the mall location boundary first.');
    }
    route['active'] = value;
    notifyListeners();
  }

  @override
  Future<void> requestMerchant(String id, String contact) async {
    if (contact.trim().length < 5) {
      throw StateError('Provide a business contact.');
    }
    requests.removeWhere((q) => q['user_id'] == userId);
    requests.add({
      'user_id': userId,
      'merchant_id': id,
      'contact': contact.trim(),
      'status': 'pending',
      'requested_at': _now,
    });
    notifyListeners();
  }

  @override
  Future<void> reviewMerchant(String user, bool approve) async {
    _requireAdmin();
    final request = requests.firstWhere((q) => q['user_id'] == user);
    request['status'] = approve ? 'approved' : 'rejected';
    request['reviewed_at'] = _now;
    if (approve) assignedMerchant = request['merchant_id'];
    notifyListeners();
  }

  @override
  Future<void> submitOffer(
    String merchant,
    String title,
    String terms,
    int stock,
    int days,
    DateTime ends,
  ) async {
    _requireShop(merchant);
    if (title.trim().isEmpty ||
        terms.trim().isEmpty ||
        stock < 0 ||
        days < 1 ||
        days > 90 ||
        !ends.isAfter(DateTime.now())) {
      throw StateError(
        'Enter a title, terms, non-negative stock, 1–90 validity days and a future campaign end.',
      );
    }
    offers.insert(0, {
      'id': _id('offer'),
      'merchant_id': merchant,
      'title': 'TEST ONLY • ${title.trim()}',
      'terms':
          'Sandbox sample. No monetary value; not accepted by shops. ${terms.trim()}',
      'stock': stock,
      'valid_days': days,
      'ends_at': ends.toUtc().toIso8601String(),
      'approval': 'pending',
      'active': false,
    });
    notifyListeners();
  }

  @override
  Future<void> approveOffer(
    JsonMap offer,
    bool approved,
    String reference,
  ) async {
    _requireAdmin();
    if (approved && reference.trim().length < 5) {
      throw StateError(
        'Enter a test approval reference of at least five characters.',
      );
    }
    offer['approval'] = approved ? 'approved' : 'rejected';
    offer['active'] = approved;
    notifyListeners();
  }

  @override
  Future<void> configureMall(
    JsonMap m,
    double lat,
    double lon,
    int radius,
    bool reviewed,
    bool qr,
  ) async {
    _requireAdmin();
    if (!lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180 ||
        radius < 50 ||
        radius > 500) {
      throw StateError(
        'Enter valid coordinates and a radius of 50–500 metres.',
      );
    }
    m.addAll({
      'latitude': lat,
      'longitude': lon,
      'radius_m': radius,
      'geofence_reviewed': reviewed,
      'qr_required': qr,
    });
    notifyListeners();
  }

  @override
  Future<JsonMap> staffToken(String route, String kind) async {
    _requireAdmin();
    final token = {
      'code': _id('qr'),
      'route_id': route,
      'kind': kind,
      'expires_at': DateTime.now()
          .add(const Duration(seconds: 60))
          .toUtc()
          .toIso8601String(),
    };
    _tokens[token['code'] as String] = token;
    return token;
  }

  void _useToken(String? code, String route, String kind) {
    final token = _tokens[code];
    if (token == null ||
        token['route_id'] != route ||
        token['kind'] != kind ||
        DateTime.parse(token['expires_at']).isBefore(DateTime.now())) {
      throw StateError('Invalid or expired sandbox staff QR.');
    }
    _tokens.remove(code);
  }

  void expireLatestVoucher() {
    if (vouchers.isEmpty) throw StateError('Claim a sample voucher first.');
    vouchers.first['expires_at'] = DateTime.now()
        .subtract(const Duration(days: 1))
        .toUtc()
        .toIso8601String();
    notifyListeners();
  }

  @override
  void dispose() {
    _steps.close();
    super.dispose();
  }
}
