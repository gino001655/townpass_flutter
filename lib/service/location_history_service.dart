import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:town_pass/bean/location_log.dart';
import 'package:town_pass/service/shared_preferences_service.dart';

class LocationHistoryService extends GetxService with WidgetsBindingObserver {
  static const MethodChannel _methodChannel = MethodChannel('townpass/location_service');
  static const EventChannel _eventChannel = EventChannel('townpass/location_stream');
  static const String _prefsKey = 'location_history_cache';

  final List<LocationLog> _logs = <LocationLog>[];
  StreamSubscription<dynamic>? _eventSubscription;
  bool _serviceRequested = false;

  SharedPreferencesService get _sharedPreferencesService => Get.find<SharedPreferencesService>();

  Future<LocationHistoryService> init() async {
    debugPrint('[LocationHistoryService] init start');
    WidgetsBinding.instance.addObserver(this);
    await _restoreFromCache();
    await _ensureServiceRunning();
    _listenToStream();
    debugPrint('[LocationHistoryService] init completed');
    return this;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[LocationHistoryService] lifecycle change: $state');
    if (state == AppLifecycleState.resumed) {
      unawaited(_ensureServiceRunning());
      unawaited(_restoreFromCache());
    }
  }

  Future<void> _ensureServiceRunning() async {
    try {
      debugPrint('[LocationHistoryService] ensure service running...');
      await _methodChannel.invokeMethod<void>('start');
      _serviceRequested = true;
      debugPrint('[LocationHistoryService] start command sent');
    } catch (error) {
      debugPrint('[LocationHistoryService] start service failed: $error');
    }
  }

  Future<void> stopService() async {
    try {
      debugPrint('[LocationHistoryService] stop service command');
      await _methodChannel.invokeMethod<void>('stop');
      _serviceRequested = false;
    } catch (error) {
      debugPrint('[LocationHistoryService] stop service failed: $error');
    }
  }

  Future<bool> isServiceRunning() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isRunning');
      debugPrint('[LocationHistoryService] isRunning -> $result');
      return result ?? false;
    } catch (error) {
      debugPrint('[LocationHistoryService] isRunning failed: $error');
      return false;
    }
  }

  void _listenToStream() {
    debugPrint('[LocationHistoryService] listen to stream');
    _eventSubscription ??=
        _eventChannel.receiveBroadcastStream().listen(_handleIncomingEvent, onError: (error) {
      debugPrint('[LocationHistoryService] stream error: $error');
    });
  }

  void _handleIncomingEvent(dynamic event) {
    debugPrint('[LocationHistoryService] event received: $event');
    if (event is! Map) {
      debugPrint('[LocationHistoryService] event ignored: not a map');
      return;
    }
    try {
      final latitudeRaw = event['latitude'];
      final longitudeRaw = event['longitude'];
      final latitude =
          latitudeRaw is num ? latitudeRaw.toDouble() : double.tryParse('$latitudeRaw');
      final longitude =
          longitudeRaw is num ? longitudeRaw.toDouble() : double.tryParse('$longitudeRaw');
      if (latitude == null || longitude == null) {
        debugPrint('[LocationHistoryService] event ignored: invalid lat/lng');
        return;
      }
      final capturedAtRaw = event['capturedAt'];
      final capturedAtUtc = capturedAtRaw is String
          ? DateTime.tryParse(capturedAtRaw)?.toUtc() ?? DateTime.now().toUtc()
          : DateTime.now().toUtc();

      final log = LocationLog(
        latitude: latitude,
        longitude: longitude,
        capturedAt: capturedAtUtc.toLocal(),
      );
      _logs.add(log);
      debugPrint(
        '[LocationHistoryService] stream lat=${log.latitude}, lng=${log.longitude}, total=${_logs.length}',
      );
      _cleanup();
      _persist();
    } catch (error) {
      debugPrint('[LocationHistoryService] handle event failed: $error');
    }
  }

  void _cleanup() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 2));
    final before = _logs.length;
    _logs.removeWhere((log) => log.capturedAt.isBefore(cutoff));
    if (before != _logs.length) {
      debugPrint(
        '[LocationHistoryService] cleanup removed ${before - _logs.length}, remaining=${_logs.length}',
      );
    }
  }

  Future<void> _restoreFromCache() async {
    debugPrint('[LocationHistoryService] restore cache start');
    final cache = _sharedPreferencesService.instance.getString(_prefsKey);
    if (cache == null || cache.isEmpty) {
      debugPrint('[LocationHistoryService] restore cache skipped (empty)');
      return;
    }
    try {
      final decoded = jsonDecode(cache);
      if (decoded is! List) {
        debugPrint('[LocationHistoryService] restore cache format mismatch');
        return;
      }
      final restored = decoded
          .whereType<Map<String, dynamic>>()
          .map(LocationLog.fromJson)
          .where(
            (log) => log.capturedAt.isAfter(
              DateTime.now().subtract(const Duration(minutes: 2)),
            ),
          )
          .toList()
        ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
      _logs
        ..clear()
        ..addAll(restored);
      debugPrint('[LocationHistoryService] restore cache loaded ${_logs.length}');
    } catch (error) {
      debugPrint('[LocationHistoryService] restore cache failed: $error');
    }
  }

  void _persist() {
    try {
      final data = jsonEncode(_logs.map((log) => log.toJson()).toList());
      _sharedPreferencesService.instance.setString(_prefsKey, data);
      debugPrint('[LocationHistoryService] persist ${_logs.length} logs');
    } catch (error) {
      debugPrint('[LocationHistoryService] persist cache failed: $error');
    }
  }

  List<LocationLog> recentLogs({
    Duration duration = const Duration(minutes: 2),
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
    debugPrint('[LocationHistoryService] clear logs & cache');
  }

  @override
  void onClose() {
    debugPrint('[LocationHistoryService] onClose');
    WidgetsBinding.instance.removeObserver(this);
    _eventSubscription?.cancel();
    _eventSubscription = null;
    super.onClose();
  }
}

