import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:town_pass/bean/location_log.dart';
import 'package:town_pass/service/geo_locator_service.dart';
import 'package:town_pass/service/shared_preferences_service.dart';

class LocationHistoryService extends GetxService with WidgetsBindingObserver {
  LocationHistoryService({Duration pollingInterval = const Duration(seconds: 10)})
      : _pollingInterval = pollingInterval;

  final Duration _pollingInterval;
  final List<LocationLog> _logs = <LocationLog>[];
  Timer? _timer;

  GeoLocatorService get _geoLocatorService => Get.find<GeoLocatorService>();
  SharedPreferencesService get _sharedPreferencesService => Get.find<SharedPreferencesService>();

  static const String _prefsKey = 'location_history_cache';

  Future<LocationHistoryService> init() async {
    WidgetsBinding.instance.addObserver(this);
    await _restoreFromCache();
    _startIfNeeded();
    return this;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _startIfNeeded();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _stop();
    }
  }

  bool get isTracking => _timer != null;

  void _startIfNeeded() {
    if (_timer != null) {
      return;
    }
    debugPrint('[LocationHistoryService] start tracking every ${_pollingInterval.inSeconds}s');
    _timer = Timer.periodic(_pollingInterval, (_) {
      unawaited(_captureOnce());
    });
    unawaited(_captureOnce());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    debugPrint('[LocationHistoryService] stop tracking, persisting ${_logs.length} logs');
    _persist();
  }

  Future<void> _captureOnce() async {
    try {
      final position = await _geoLocatorService.position();
      final log = LocationLog(
        latitude: position.latitude,
        longitude: position.longitude,
        capturedAt: DateTime.now(),
      );
      _logs.add(log);
      debugPrint('[LocationHistoryService] capture lat=${log.latitude}, lng=${log.longitude}, total=${_logs.length}');
      _cleanup();
      _persist();
    } catch (error) {
      debugPrint('[LocationHistoryService] capture failed: $error');
    }
  }

  void _cleanup() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 30));
    _logs.removeWhere((log) => log.capturedAt.isBefore(cutoff));
    debugPrint('[LocationHistoryService] cleanup older than $cutoff, remaining=${_logs.length}');
  }

  Future<void> _restoreFromCache() async {
    final cache = _sharedPreferencesService.instance.getString(_prefsKey);
    if (cache == null || cache.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(cache);
      if (decoded is List) {
        final restored = decoded
            .whereType<Map<String, dynamic>>()
            .map(LocationLog.fromJson)
            .where((log) =>
                log.capturedAt.isAfter(DateTime.now().subtract(const Duration(minutes: 30))))
            .toList()
          ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
        _logs
          ..clear()
          ..addAll(restored);
        debugPrint('[LocationHistoryService] restore from cache, loaded ${_logs.length} logs');
      }
    } catch (error) {
      debugPrint('[LocationHistoryService] restore cache failed: $error');
    }
  }

  void _persist() {
    try {
      final cache = jsonEncode(_logs.map((log) => log.toJson()).toList());
      _sharedPreferencesService.instance.setString(_prefsKey, cache);
      debugPrint('[LocationHistoryService] persist ${_logs.length} logs');
    } catch (error) {
      debugPrint('[LocationHistoryService] persist cache failed: $error');
    }
  }

  List<LocationLog> recentLogs({
    Duration duration = const Duration(minutes: 30),
    int? limit,
  }) {
    final cutoff = DateTime.now().subtract(duration);
    final filtered = _logs
        .where((log) => log.capturedAt.isAfter(cutoff))
        .toList()
      ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

    if (limit == null || filtered.length <= limit) {
      return filtered;
    }
    return filtered.sublist(filtered.length - limit);
  }

  void clear() {
    _logs.clear();
    _sharedPreferencesService.instance.remove(_prefsKey);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.onClose();
  }
}

