import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'package:town_pass/service/account_service.dart';
import 'package:town_pass/service/device_service.dart';
import 'package:town_pass/service/geo_locator_service.dart';
import 'package:town_pass/service/location_history_service.dart';
import 'package:town_pass/service/notification_service.dart';
import 'package:town_pass/service/shared_preferences_service.dart';
import 'package:town_pass/service/subscription_service.dart';
import 'package:town_pass/util/tp_button.dart';
import 'package:town_pass/util/tp_dialog.dart';
import 'package:town_pass/util/tp_route.dart';
import 'package:town_pass/util/tp_text.dart';
import 'package:town_pass/util/web_message_handler/tp_web_message_reply.dart';
import 'package:url_launcher/url_launcher.dart';

abstract class TPWebMessageHandler {
  String get name;

  Future<void> handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required Function(WebMessage replyWebMessage)? onReply,
  });

  WebMessage replyWebMessage({required Object? data}) {
    return TPWebStringMessageReply(
      name: name,
      data: data,
    ).message;
  }
}

class UserinfoWebMessageHandler extends TPWebMessageHandler {
  @override
  String get name => 'userinfo';

  @override
  Future<void> handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required onReply,
  }) async {
    onReply?.call(replyWebMessage(
      data: Get.find<AccountService>().account ?? [],
    ));
  }
}

class LaunchMapWebMessageHandler extends TPWebMessageHandler {
  @override
  String get name => 'launch_map';

  @override
  handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required Function(WebMessage reply)? onReply,
  }) async {
    if (message == null || message is! String) {
      onReply?.call(
        replyWebMessage(data: false),
      );
    }
    final Uri uri = Uri.parse(message as String);
    final bool canLaunch = await canLaunchUrl(uri);

    onReply?.call(
      replyWebMessage(data: canLaunch),
    );

    if (canLaunch) {
      await launchUrl(uri);
    }
  }
}

class Agree1999MessageHandler extends TPWebMessageHandler {
  @override
  String get name => '1999agree';

  @override
  handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required Function(WebMessage reply)? onReply,
  }) async {
    if (message == null) {
      onReply?.call(
        replyWebMessage(data: false),
      );
    }
    final Uri uri = Uri.parse('tel://1999');

    final bool canLaunch = await canLaunchUrl(uri);
    if (!canLaunch) {
      onReply?.call(replyWebMessage(data: false));
      return;
    }

    final bool userAgreement = SharedPreferencesService().instance.getBool(SharedPreferencesService.keyPhoneCallUserAgreement) ?? false;
    if (!userAgreement) {
      await Get.toNamed(TPRoute.phoneCallUserAgreement);

      final bool userAgreement = SharedPreferencesService().instance.getBool(SharedPreferencesService.keyPhoneCallUserAgreement) ?? false;
      if (!userAgreement) {
        onReply?.call(replyWebMessage(data: false));
        return;
      }
    }

    await TPDialog.show(
      padding: const EdgeInsets.symmetric(horizontal: 68, vertical: 40),
      showCloseCross: true,
      barrierDismissible: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Assets.svg.phoneCallService.svg(),
          const TPText('語音通報', style: TPTextStyles.titleSemiBold),
          const SizedBox(height: 8),
          const TPText('電話撥號'),
          const SizedBox(height: 24),
          TPButton.primary(
            text: '立即撥號',
            onPressed: () async => await launchUrl(uri),
          ),
        ],
      ),
    );
  }
}

class PhoneCallMessageHandler extends TPWebMessageHandler {
  @override
  String get name => 'phone_call';

  @override
  handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required Function(WebMessage reply)? onReply,
  }) async {
    if (message == null) {
      onReply?.call(
        replyWebMessage(data: false),
      );
    }
    final Uri uri = Uri.parse('tel://${message!}');
    final bool canLaunch = await canLaunchUrl(uri);

    onReply?.call(
      replyWebMessage(data: canLaunch),
    );

    if (canLaunch) {
      await launchUrl(uri);
    }
  }
}

class LocationMessageHandler extends TPWebMessageHandler {
  @override
  String get name => 'location';

  @override
  handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required Function(WebMessage reply)? onReply,
  }) async {
    Position? position;

    // might have permission issue
    try {
      position = await Get.find<GeoLocatorService>().position();
    } catch (error) {
      printError(info: error.toString());
    }

    onReply?.call(replyWebMessage(
      data: position?.toJson() ?? [],
    ));
  }
}

class LocationHistoryMessageHandler extends TPWebMessageHandler {
  @override
  String get name => 'location_history';

  Duration _parseDuration(Object? message) {
    if (message is Map && message['minutes'] is num) {
      final minutes = (message['minutes'] as num).clamp(1, 180).toInt();
      return Duration(minutes: minutes);
    }
    return const Duration(minutes: 30);
  }

  int? _parseLimit(Object? message) {
    if (message is Map && message['limit'] is num) {
      final limit = (message['limit'] as num).toInt();
      if (limit <= 0) {
        return null;
      }
      return limit;
    }
    return null;
  }

  @override
  Future<void> handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required Function(WebMessage replyWebMessage)? onReply,
  }) async {
    final service = Get.find<LocationHistoryService>();
    final duration = _parseDuration(message);
    final limit = _parseLimit(message);
    final logs = service
        .recentLogs(duration: duration, limit: limit)
        .map((log) => log.toJson())
        .toList();

    onReply?.call(
      replyWebMessage(
        data: logs,
      ),
    );
  }
}

class LocationPermissionStatusMessageHandler extends TPWebMessageHandler {
  @override
  String get name => 'location_permission_status';

  @override
  Future<void> handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required Function(WebMessage replyWebMessage)? onReply,
  }) async {
    final status = await Get.find<LocationHistoryService>().permissionStatus();
    onReply?.call(replyWebMessage(data: status));
  }
}

class LocationPermissionRequestMessageHandler extends TPWebMessageHandler {
  @override
  String get name => 'location_permission_request';

  @override
  Future<void> handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required Function(WebMessage replyWebMessage)? onReply,
  }) async {
    final status = await Get.find<LocationHistoryService>().requestPermission();
    onReply?.call(replyWebMessage(data: status));
  }
}

class LocationPermissionOpenSettingsMessageHandler extends TPWebMessageHandler {
  @override
  String get name => 'location_permission_open_settings';

  @override
  Future<void> handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required Function(WebMessage replyWebMessage)? onReply,
  }) async {
    final response = await Get.find<LocationHistoryService>().openAppSettings();
    onReply?.call(replyWebMessage(data: response));
  }
}

class DeviceInfoMessageHandler extends TPWebMessageHandler {
  @override
  String get name => 'deviceinfo';

  @override
  handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required Function(WebMessage reply)? onReply,
  }) async {
    onReply?.call(replyWebMessage(
      data: Get.find<DeviceService>().baseDeviceInfo?.data ?? [],
    ));
  }
}

class OpenLinkMessageHandler extends TPWebMessageHandler {
  @override
  String get name => 'open_link';

  @override
  handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required Function(WebMessage reply)? onReply,
  }) async {
    switch (message as String?) {
      case String uri:
        await TPRoute.openUri(uri: uri);
      case null:
        onReply?.call(replyWebMessage(data: false));
    }
  }
}

class NotifyMessageHandler extends TPWebMessageHandler {
  @override
  String get name => 'notify';

  @override
  Future<void> handle(
      {required Object? message,
      required WebUri? sourceOrigin,
      required bool isMainFrame,
      required Function(
        WebMessage replyWebMessage,
      )? onReply}) async {
    switch (message) {
      case Object json when json is Map<String, dynamic>:
        NotificationService.showNotification(
          title: json['title'],
          content: json['content'],
        );
        final String content = json['content'];
        if (RegExp(r'已訂閱(.+)').hasMatch(content)) {
          final String target = RegExp(r'已訂閱(.+)').firstMatch(content)!.group(1)!;
          Get.find<SubscriptionService>().addSubscription(title: target);
        } else if (RegExp(r'已取消訂閱(.+)').hasMatch(content)) {
          final String target = RegExp(r'已取消訂閱(.+)').firstMatch(content)!.group(1)!;
          Get.find<SubscriptionService>().removeSubscription(title: target);
        }
      default:
        onReply?.call(replyWebMessage(data: false));
        return;
    }
  }
}

class QRCodeScanMessageHandler extends TPWebMessageHandler {
  @override
  String get name => 'qr_code_scan';

  @override
  Future<void> handle({
    required Object? message,
    required WebUri? sourceOrigin,
    required bool isMainFrame,
    required onReply,
  }) async {
    final result = await Get.toNamed(TPRoute.qrCodeScan);
    onReply?.call(
      replyWebMessage(data: result),
    );
  }
}
