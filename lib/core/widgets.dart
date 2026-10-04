import 'package:flutter/material.dart';

import 'theme.dart';

class AppPanel extends StatelessWidget {
  const AppPanel({required this.child, this.padding = const EdgeInsets.all(20), super.key});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line.withValues(alpha: 0.78)),
        boxShadow: const [
          BoxShadow(color: Color(0x0713273D), blurRadius: 22, offset: Offset(0, 7)),
        ],
      ),
      child: child,
    );
  }
}

class PageHeading extends StatelessWidget {
  const PageHeading({
    required this.title,
    required this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 5),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted, height: 1.4)),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        else if (icon != null)
          Icon(icon, size: 18),
        if (busy || icon != null) const SizedBox(width: 8),
        Text(label),
      ],
    );
    return ElevatedButton(onPressed: busy ? null : onPressed, child: child);
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({this.label = 'Loading…', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(height: 14),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
      ),
    );
  }
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(17),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFCA4B50)),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(color: AppColors.ink, height: 1.4))),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}

class EmptyNotice extends StatelessWidget {
  const EmptyNotice({required this.title, required this.subtitle, this.icon = Icons.inbox_outlined, super.key});

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(color: AppColors.softBlue, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.blue, size: 24),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 5),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    required this.title,
    required this.value,
    required this.footnote,
    required this.icon,
    required this.tint,
    super.key,
  });

  final String title;
  final String value;
  final String footnote;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 13))),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: tint.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: tint, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.ink, letterSpacing: -0.8)),
          const SizedBox(height: 4),
          Text(footnote, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({required this.name, this.size = 42, super.key});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    final initials = parts.isEmpty ? 'FF' : parts.take(2).map((part) => part.substring(0, 1)).join().toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.softBlue,
        borderRadius: BorderRadius.circular(size / 2.7),
      ),
      child: Text(initials, style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.w800, fontSize: size * 0.31)),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final (color, fill, label) = switch (normalized) {
      'approved' || 'active' || 'present' => (AppColors.success, AppColors.softGreen, _titleCase(status)),
      'rejected' || 'inactive' => (const Color(0xFFC94D54), AppColors.softRed, _titleCase(status)),
      'pending' || 'on_leave' => (const Color(0xFFAE751C), AppColors.softAmber, _titleCase(status)),
      'cancelled' => (AppColors.muted, const Color(0xFFF0F3F7), _titleCase(status)),
      _ => (AppColors.muted, const Color(0xFFF0F3F7), _titleCase(status)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(40)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value.replaceAll('_', ' ').split(' ').map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}').join(' ');
}

String formatDateTime(Object? raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '');
  if (date == null) return '—';
  final local = date.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day} ${_month(local.month)} · $hour:$minute $period';
}

String formatDate(Object? raw) {
  final date = DateTime.tryParse(raw?.toString() ?? '');
  if (date == null) return '—';
  return '${date.day} ${_month(date.month)} ${date.year}';
}

String _month(int month) => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][month - 1];
