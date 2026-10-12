import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef JsonMap = Map<String, dynamic>;

class StepAccumulator {
  int steps;
  int? _last;
  StepAccumulator([this.steps = 0]);
  // Foreground deltas exclude pre-session totals and paused movement.
  void addReading(int total) {
    if (total < 0) return;
    if (_last != null && total >= _last!) steps += total - _last!;
    _last = total;
  }

  void resume() => _last = null;
}

class LangkahStore extends ChangeNotifier {
  final SupabaseClient? client;
  LangkahStore({this.client});
  bool loading = false, roleReady = false;
  String? loadError, assignedMerchant;
  String role = 'resident', selectedMall = 'elmina';
  List<JsonMap> malls = [],
      merchants = [],
      routes = [],
      offers = [],
      vouchers = [],
      reports = [],
      history = [],
      requests = [];
  JsonMap? session;
  bool get signedIn => client?.auth.currentUser != null;
  String? get userId => client?.auth.currentUser?.id;
  String? get email => client?.auth.currentUser?.email;
  String get name =>
      client?.auth.currentUser?.userMetadata?['display_name'] as String? ??
      'Walker';
  JsonMap? mallFor(String? id) => malls.where((m) => m['id'] == id).firstOrNull;
  JsonMap? merchantFor(String? id) =>
      merchants.where((m) => m['id'] == id).firstOrNull;
  String shopLabel(String? id) {
    final m = merchantFor(id);
    return m == null ? 'Shop' : '${m['name']} • ${m['lot']}';
  }

  JsonMap? routeFor(String? id) =>
      routes.where((r) => r['id'] == id).firstOrNull;
  JsonMap? offerFor(String? id) =>
      offers.where((o) => o['id'] == id).firstOrNull;
  List<JsonMap> get mallRoutes =>
      routes.where((r) => r['mall_id'] == selectedMall).toList();
  List<JsonMap> get mallShops =>
      merchants.where((m) => m['mall_id'] == selectedMall).toList();
  List<JsonMap> offersAt(String mall) => offers
      .where(
        (o) =>
            o['approval'] == 'approved' &&
            o['active'] == true &&
            (o['stock'] as num) > 0 &&
            o['ends_at'] != null &&
            DateTime.parse(o['ends_at']).isAfter(DateTime.now()) &&
            merchantFor(o['merchant_id'])?['mall_id'] == mall,
      )
      .toList();
  List<JsonMap> get availableOffers => offersAt(
    routeFor(session?['route_id'])?['mall_id'] ?? selectedMall,
  ).take(3).toList();
  List<JsonMap> get staffOffers => offers
      .where(
        (o) =>
            merchantFor(o['merchant_id']) != null &&
            (role == 'admin' || o['merchant_id'] == assignedMerchant),
      )
      .toList();
  List<JsonMap> get myVouchers =>
      vouchers.where((v) => v['user_id'] == userId).toList();
  String status(JsonMap v) => v['redeemed_at'] != null
      ? 'Redeemed'
      : DateTime.parse(v['expires_at']).isBefore(DateTime.now())
      ? 'Expired'
      : 'Available';
  void selectMall(String id) {
    selectedMall = id;
    notifyListeners();
  }

  static List<JsonMap> rows(dynamic value) =>
      (value as List).map((v) => JsonMap.from(v as Map)).toList();
  Future<void> signOut() async {
    await client?.auth.signOut();
    role = 'resident';
    roleReady = false;
    assignedMerchant = null;
    session = null;
    malls = [];
    merchants = [];
    routes = [];
    offers = [];
    vouchers = [];
    reports = [];
    history = [];
    requests = [];
    loadError = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (client == null || !signedIn || loading) return;
    final user = client!.auth.currentUser!.id;
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      final profile = JsonMap.from(await client!.rpc('langkah_profile'));
      final results = await Future.wait([
        client!.from('langkah_malls').select().order('name'),
        client!
            .from('langkah_merchants')
            .select()
            .eq('listed', true)
            .order('name'),
        client!
            .from('langkah_routes')
            .select()
            .not('id', 'in', '(mall-loop,lakeside-loop)')
            .order('minutes'),
        client!.from('langkah_offers').select().order('id'),
        client!
            .from('langkah_vouchers')
            .select()
            .order('issued_at', ascending: false),
        client!
            .from('langkah_sessions')
            .select()
            .order('started_at', ascending: false),
        client!
            .from('langkah_reports')
            .select()
            .order('created_at', ascending: false),
        client!
            .from('langkah_merchant_requests')
            .select()
            .order('requested_at', ascending: false),
      ]);
      if (client!.auth.currentUser?.id != user) return;
      role = profile['role'];
      roleReady = true;
      assignedMerchant = profile['merchant_id'];
      malls = rows(results[0]);
      merchants = rows(results[1]);
      routes = rows(results[2]);
      offers = rows(results[3]);
      vouchers = rows(results[4]);
      history = rows(results[5]);
      reports = rows(results[6]);
      requests = rows(results[7]);
      session = history
          .where(
            (s) =>
                s['user_id'] == user &&
                ['walking', 'eligible'].contains(s['status']),
          )
          .firstOrNull;
    } catch (e) {
      loadError = 'Could not load Langkah. ${friendlyError(e)}';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  JsonMap locationParams(JsonMap l) => {
    'p_lat': l['latitude'],
    'p_lon': l['longitude'],
    'p_accuracy': l['accuracy'],
    'p_age_ms': l['age_ms'],
  };
  Future<JsonMap> start(
    JsonMap route, {
    required JsonMap location,
    String? code,
  }) async {
    session = JsonMap.from(
      await client!.rpc(
        'langkah_begin',
        params: {
          'p_route': route['id'],
          ...locationParams(location),
          'p_code': code,
        },
      ),
    );
    notifyListeners();
    return session!;
  }

  Future<void> progress(int steps, JsonMap location) async {
    if (session == null) throw StateError('Start a mission first.');
    session = JsonMap.from(
      await client!.rpc(
        'langkah_track',
        params: {
          'p_session': session!['id'],
          'p_steps': steps,
          ...locationParams(location),
        },
      ),
    );
    notifyListeners();
  }

  Future<void> checkpoint(String code, JsonMap location) async {
    session = JsonMap.from(
      await client!.rpc(
        'langkah_finish_checkpoint',
        params: {
          'p_session': session!['id'],
          'p_code': code,
          ...locationParams(location),
        },
      ),
    );
    notifyListeners();
  }

  Future<JsonMap> claim(String offerId) async {
    if (session == null) throw StateError('Start a mission first.');
    final v = JsonMap.from(
      await client!.rpc(
        'langkah_claim',
        params: {'p_session': session!['id'], 'p_offer': offerId},
      ),
    );
    await refresh();
    return v;
  }

  Future<void> cancel() async {
    if (session == null) return;
    await client!.rpc('langkah_cancel', params: {'p_session': session!['id']});
    await refresh();
  }

  Future<JsonMap> redeem(String code) async {
    final v = JsonMap.from(
      await client!.rpc('langkah_redeem', params: {'p_code': code}),
    );
    await refresh();
    return v;
  }

  Future<void> refreshVoucher(String id) async {
    final value = await client!
        .from('langkah_vouchers')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (value != null) {
      final i = vouchers.indexWhere((v) => v['id'] == id);
      if (i >= 0) {
        vouchers[i] = JsonMap.from(value);
        notifyListeners();
      }
    }
  }

  Future<void> report(
    String routeId,
    String category,
    String description,
  ) async {
    if (description.trim().length < 5) {
      throw StateError('Describe the issue in at least five characters.');
    }
    await client!.from('langkah_reports').insert({
      'user_id': client!.auth.currentUser!.id,
      'route_id': routeId,
      'category': category,
      'description': description.trim(),
    });
    await refresh();
  }

  Future<void> setOffer(JsonMap offer, int stock, bool active) async {
    await client!.rpc(
      'langkah_offer_stock',
      params: {'p_offer': offer['id'], 'p_stock': stock, 'p_active': active},
    );
    await refresh();
  }

  Future<void> resolve(JsonMap report, bool value) async {
    await client!
        .from('langkah_reports')
        .update({'resolved': value})
        .eq('id', report['id']);
    await refresh();
  }

  Future<void> setRoute(JsonMap route, bool value) async {
    if (value && mallFor(route['mall_id'])?['geofence_reviewed'] != true) {
      throw StateError('Review the mall location boundary first.');
    }
    await client!
        .from('langkah_routes')
        .update({'active': value})
        .eq('id', route['id']);
    await refresh();
  }

  Future<void> requestMerchant(String id, String contact) async {
    await client!.rpc(
      'langkah_request_merchant',
      params: {'p_merchant': id, 'p_contact': contact},
    );
    await refresh();
  }

  Future<void> reviewMerchant(String user, bool approve) async {
    await client!.rpc(
      'langkah_review_merchant',
      params: {'p_user': user, 'p_approve': approve},
    );
    await refresh();
  }

  Future<void> submitOffer(
    String merchant,
    String title,
    String terms,
    int stock,
    int days,
    DateTime ends,
  ) async {
    await client!.rpc(
      'langkah_submit_offer',
      params: {
        'p_merchant': merchant,
        'p_title': title,
        'p_terms': terms,
        'p_stock': stock,
        'p_days': days,
        'p_ends': ends.toUtc().toIso8601String(),
      },
    );
    await refresh();
  }

  Future<void> approveOffer(
    JsonMap offer,
    bool approved,
    String reference,
  ) async {
    await client!.rpc(
      'langkah_approve_offer',
      params: {
        'p_offer': offer['id'],
        'p_approve': approved,
        'p_reference': reference,
      },
    );
    await refresh();
  }

  Future<void> configureMall(
    JsonMap m,
    double lat,
    double lon,
    int radius,
    bool reviewed,
    bool qr,
  ) async {
    await client!.rpc(
      'langkah_configure_mall',
      params: {
        'p_mall': m['id'],
        'p_lat': lat,
        'p_lon': lon,
        'p_radius': radius,
        'p_reviewed': reviewed,
        'p_qr': qr,
      },
    );
    await refresh();
  }

  Future<JsonMap> staffToken(String route, String kind) async => JsonMap.from(
    await client!.rpc(
      'langkah_staff_token',
      params: {'p_route': route, 'p_kind': kind},
    ),
  );
}

String friendlyError(Object e) {
  if (e is PlatformException) {
    return e.message ?? 'Your phone could not complete this check. Try again.';
  }
  if (e is AuthException) return e.message;
  if (e is PostgrestException) {
    return e.code == 'PGRST205' || e.code == 'PGRST202'
        ? 'Install the latest database migration, then refresh.'
        : e.message;
  }
  if (e is StateError) return e.message;
  return e.toString().replaceFirst('Exception: ', '');
}
