import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:town_pass/bean/location_log.dart';
import 'package:town_pass/service/geo_locator_service.dart';

class LocationHistoryService extends GetxService with WidgetsBindingObserver {
  LocationHistoryService({Duration pollingInterval = const Duration(seconds: 10)})
      : _pollingInterval = pollingInterval;

  final Duration _pollingInterval;
  final List<LocationLog> _logs = <LocationLog>[];
  Timer? _timer;

  GeoLocatorService get _geoLocatorService => Get.find<GeoLocatorService>();

  Future<LocationHistoryService> init() async {
    WidgetsBinding.instance.addObserver(this);
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
    _timer = Timer.periodic(_pollingInterval, (_) {
      unawaited(_captureOnce());
    });
    unawaited(_captureOnce());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
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
      _cleanup();
    } catch (error) {
      debugPrint('[LocationHistoryService] capture failed: $error');
    }
  }

  void _cleanup() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 30));
    _logs.removeWhere((log) => log.capturedAt.isBefore(cutoff));
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
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.onClose();
  }
}

