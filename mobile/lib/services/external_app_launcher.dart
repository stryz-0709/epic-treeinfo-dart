import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class EarthRangerLauncher {
  EarthRangerLauncher._();

  static const MethodChannel _channel =
      MethodChannel('com.epictech.vranger/app_launcher');

  static const String _androidPackageName = 'com.earthranger';
  static final Uri _androidStoreUri = Uri.parse(
    'market://details?id=$_androidPackageName',
  );
  static final Uri _androidStoreWebUri = Uri.parse(
    'https://play.google.com/store/apps/details?id=$_androidPackageName',
  );
  static final Uri _iosEntryUri = Uri.parse('https://pamdas.org');
  static final Uri _iosStoreUri = Uri.parse(
    'https://apps.apple.com/app/id1636950688',
  );

  static Future<bool> open() async {
    if (kIsWeb) {
      return false;
    }

    try {
      if (Platform.isAndroid) {
        final opened = await _openByPackageName(_androidPackageName);
        if (opened) {
          return true;
        }
        return _openAndroidStore();
      }

      if (Platform.isIOS) {
        if (await canLaunchUrl(_iosEntryUri)) {
          return launchUrl(_iosEntryUri, mode: LaunchMode.externalApplication);
        }

        if (await canLaunchUrl(_iosStoreUri)) {
          return launchUrl(_iosStoreUri, mode: LaunchMode.externalApplication);
        }

        return false;
      }

      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _openAndroidStore() async {
    if (await canLaunchUrl(_androidStoreUri)) {
      final opened = await launchUrl(
        _androidStoreUri,
        mode: LaunchMode.externalApplication,
      );
      if (opened) {
        return true;
      }
    }

    if (await canLaunchUrl(_androidStoreWebUri)) {
      return launchUrl(_androidStoreWebUri, mode: LaunchMode.externalApplication);
    }

    return false;
  }

  static Future<bool> _openByPackageName(String packageName) async {
    try {
      final opened = await _channel.invokeMethod<bool>('openAppByPackage', {
        'packageName': packageName,
      });
      return opened ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

class ExternalAppLauncher {
  ExternalAppLauncher._();

  static Future<bool> openEarthRanger() => EarthRangerLauncher.open();
}
