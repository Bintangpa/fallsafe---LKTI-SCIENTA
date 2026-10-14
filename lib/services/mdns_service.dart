import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

class MdnsDiscoveryResult {
  final bool success;
  final String? ip;
  final int port;
  final String wsUrl;
  final String message;

  MdnsDiscoveryResult({
    required this.success,
    this.ip,
    this.port = 81,
    required this.wsUrl,
    required this.message,
  });
}

class MdnsService {
  static const String defaultHostname = 'fallsafe.local';
  static const int defaultPort = 81;
  static const String defaultEndpoint = 'ws://$defaultHostname:$defaultPort';
  static const String fallbackApEndpoint = 'ws://192.168.4.1:$defaultPort';

  /// Menyelesaikan hostname mDNS (misal fallsafe.local) menjadi alamat IP sebenarnya
  static Future<String?> resolveHostname(String host, {Duration timeout = const Duration(seconds: 3)}) async {
    final cleanHost = host.trim().replaceAll(RegExp(r'^https?://|^wss?://'), '').split(':').first;

    // 1. Coba lookup standar (OS resolver / iOS / Desktop / Android mDNS-capable)
    try {
      final addresses = await InternetAddress.lookup(cleanHost).timeout(timeout);
      for (final addr in addresses) {
        if (addr.type == InternetAddressType.IPv4) {
          return addr.address;
        }
      }
      if (addresses.isNotEmpty) {
        return addresses.first.address;
      }
    } catch (_) {}

    // 2. Jika OS lookup gagal (kebiasaan Android pada domain .local), gunakan multicast_dns
    if (!kIsWeb) {
      try {
        final MDnsClient client = MDnsClient();
        await client.start();

        final queryHost = cleanHost.endsWith('.') ? cleanHost : '$cleanHost.';
        String? foundIp;

        final stream = client.lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv4(queryHost),
        );

        await for (final record in stream.timeout(timeout, onTimeout: (sink) => sink.close())) {
          final addr = record.address;
          if (addr.type == InternetAddressType.IPv4) {
            foundIp = addr.address;
            break;
          }
        }

        client.stop();
        if (foundIp != null) return foundIp;
      } catch (e) {
        print('MdnsService multicast_dns lookup error: $e');
      }
    }

    return null;
  }

  /// Otomatis memindai dan mendeteksi sensor mDNS di jaringan Wi-Fi
  static Future<MdnsDiscoveryResult> discoverSensor({String hostname = defaultHostname, int port = defaultPort}) async {
    // 1. Coba selesaikan hostname mDNS fallsafe.local
    final ip = await resolveHostname(hostname, timeout: const Duration(seconds: 4));
    if (ip != null) {
      final wsUrl = 'ws://$ip:$port';
      return MdnsDiscoveryResult(
        success: true,
        ip: ip,
        port: port,
        wsUrl: wsUrl,
        message: 'Sensor ditemukan melalui mDNS: $hostname ($ip:$port)',
      );
    }

    // 2. Cek apakah perangkat sedang terhubung ke Access Point langsung Wemos (192.168.4.1)
    try {
      final socket = await Socket.connect('192.168.4.1', port, timeout: const Duration(milliseconds: 1500));
      socket.destroy();
      return MdnsDiscoveryResult(
        success: true,
        ip: '192.168.4.1',
        port: port,
        wsUrl: 'ws://192.168.4.1:$port',
        message: 'Sensor terdeteksi pada mode Access Point Wemos (192.168.4.1:$port)',
      );
    } catch (_) {}

    // 3. Fallback mDNS URL standar
    return MdnsDiscoveryResult(
      success: false,
      wsUrl: 'ws://$hostname:$port',
      message: 'Perangkat $hostname belum ditemukan di jaringan Wi-Fi saat ini.',
    );
  }

  /// Membantu mendapatkan URL WebSocket siap pakai dari string input
  /// Jika berupa fallsafe.local, otomatis dicoba resolve ke IP jika memungkinkan
  static Future<String> getResolvedWsUrl(String rawUrl) async {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return defaultEndpoint;

    try {
      final uri = Uri.parse(trimmed.startsWith('ws://') || trimmed.startsWith('wss://') ? trimmed : 'ws://$trimmed');
      final host = uri.host;
      final port = uri.port != 0 ? uri.port : defaultPort;

      if (host.toLowerCase().endsWith('.local')) {
        final ip = await resolveHostname(host, timeout: const Duration(seconds: 2));
        if (ip != null) {
          return 'ws://$ip:$port';
        }
      }
      return uri.toString();
    } catch (_) {
      return trimmed;
    }
  }
}
