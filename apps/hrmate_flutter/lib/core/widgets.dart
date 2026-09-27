import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api.dart';
import 'theme.dart';

/// JSON list → mutable list of mutable maps (safe to patch in place for
/// optimistic UI updates like likes / toggles).
List<Map<String, dynamic>> asMaps(Object? v) {
  if (v is! List) return <Map<String, dynamic>>[];
  return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// ₹ 31,240 style (Indian grouping, whole rupees).
String inr(Object? n) => _inr.format(n is num ? n : num.tryParse('$n') ?? 0);

const kMonthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const kMonthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const kDowShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "12 Oct, 4:05 PM" for ISO timestamps coming from the API.
String shortStamp(Object? iso) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '${d.day} ${kMonthsShort[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} $ampm';
}

/// Round avatar: relative/absolute server photo with an initial fallback.
/// Callers can supply auth headers for protected same-origin photo endpoints.
class HmAvatar extends StatelessWidget {
  final String name;
  final String? photo;
  final double radius;
  final Map<String, String>? headers;
  const HmAvatar({super.key, required this.name, this.photo, this.radius = 20, this.headers});

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final base = Uri.parse(kApiBaseUrl);
    final parsed = photo == null ? null : Uri.tryParse(photo!);
    final resolved = parsed == null ? null : base.resolveUri(parsed);
    final url = resolved != null && ['http', 'https'].contains(resolved.scheme) ? resolved : null;
    final sameOrigin = url != null && url.scheme == base.scheme && url.host == base.host && url.port == base.port;
    return CircleAvatar(
      radius: radius,
      backgroundColor: HMC.primaryFade,
      // Protected API photos need Bearer auth on native. Never forward the
      // token to an external legacy photo URL stored on an employee profile.
      foregroundImage: url != null ? NetworkImage(url.toString(), headers: sameOrigin ? headers : null) : null,
      onForegroundImageError: url != null ? (_, __) {} : null,
      child: Text(
        initial,
        style: TextStyle(color: HMC.primaryDark, fontWeight: FontWeight.w900, fontSize: radius * 0.8),
      ),
    );
  }
}

/// Centered message + optional retry — used by every P5 list on error/empty.
class HmMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? hint;
  final VoidCallback? onRetry;
  final String retryLabel;
  const HmMessage({
    super.key,
    required this.icon,
    required this.text,
    this.hint,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 44, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w800, color: HMC.ink, fontSize: 15),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5)),
        ],
        if (onRetry != null) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(retryLabel)),
        ],
      ]),
    );
  }
}

/// Snack helper with brand colours.
void hmToast(BuildContext context, String msg, {bool ok = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? HMC.emeraldDeep : HMC.ink,
      behavior: SnackBarBehavior.floating,
    ));
}
