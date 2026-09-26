import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

const _emerald500 = Color(0xFF10B981);
const _emerald600 = Color(0xFF059669);
const _emerald700 = Color(0xFF047857);
const _slate700 = Color(0xFF334155);
const _slate800 = Color(0xFF1E293B);

/// Letter sheet view (web /letters/[id] parity): the exact company letterhead —
/// header rule, ref/dated row, addressee, underlined title, justified body,
/// official seal + signatory — plus Share / PDF (public token link, same as
/// payslips) and Copy link.
class LetterViewScreen extends ConsumerStatefulWidget {
  final String id;
  const LetterViewScreen({super.key, required this.id});

  @override
  ConsumerState<LetterViewScreen> createState() => _LetterViewScreenState();
}

class _LetterViewScreenState extends ConsumerState<LetterViewScreen> {
  Map<String, dynamic>? _doc;
  bool _loading = true;
  bool _sharing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _lang => ref.read(langProvider);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(apiProvider).get<Map<String, dynamic>>(
            '/api/letters/${widget.id}',
            queryParameters: {'lang': _lang},
          );
      final doc = res.data?['letter'];
      if (!mounted) return;
      setState(() {
        _doc = doc is Map ? Map<String, dynamic>.from(doc) : null;
        _loading = false;
      });
    } on DioException catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _shareUrl() async {
    final res = await ref.read(apiProvider).post<Map<String, dynamic>>('/api/letters/${widget.id}/share');
    final url = res.data?['url'];
    if (url is String) return url;
    final path = res.data?['path'];
    return path is String ? '$kApiBaseUrl$path' : null;
  }

  Future<void> _share({required bool copyOnly}) async {
    final lang = _lang;
    setState(() => _sharing = true);
    try {
      final url = await _shareUrl();
      if (url == null || !mounted) return;
      if (copyOnly) {
        await Clipboard.setData(ClipboardData(text: url));
        if (mounted) hmToast(context, T.s('Link copied ✔', lang), ok: true);
      } else {
        await SharePlus.instance.share(ShareParams(
          text: '${T.s('Letter', lang)} — ${_doc?['ref']}\n$url',
          subject: '${_doc?['ref']}',
        ));
      }
    } catch (e) {
      if (mounted) hmToast(context, apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(langProvider);
    final doc = _doc;

    return Scaffold(
      backgroundColor: HMC.bg,
      appBar: AppBar(title: Text(T.s('Letter', lang)), centerTitle: false),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: HMC.primary))
          : _error != null || doc == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error ?? 'Letter not found.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5)),
                      const SizedBox(height: 10),
                      FilledButton.tonal(onPressed: _load, child: Text(T.s('Retry', lang))),
                    ]),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(14, 10, 14, 18), children: [
                  // Ref bar + Share / PDF pill (mockup p7-my-letters)
                  Row(children: [
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: '${_s(doc, ['labels', 'ref'])} ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                        TextSpan(text: '${doc['ref']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: HMC.ink)),
                      ])),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _emerald600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                      ),
                      onPressed: _sharing ? null : () => _share(copyOnly: false),
                      child: Text(T.s('Share / PDF', lang)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  _sheet(doc),
                ]),
      bottomNavigationBar: doc == null
          ? null
          : SafeArea(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Row(children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _emerald600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                      ),
                      onPressed: _sharing ? null : () => _share(copyOnly: false),
                      child: Text(T.s('Share / PDF', lang)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HMC.ink,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                      ),
                      onPressed: _sharing ? null : () => _share(copyOnly: true),
                      child: Text(T.s('Copy link', lang)),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }

  String _s(Map<String, dynamic> m, List<String> path) {
    Object? cur = m;
    for (final k in path) {
      cur = (cur is Map ? cur[k] : null);
    }
    return '${cur ?? ''}';
  }

  Widget _sheet(Map<String, dynamic> doc) {
    final header = Map<String, dynamic>.from(doc['header'] as Map? ?? const {});
    final labels = Map<String, dynamic>.from(doc['labels'] as Map? ?? const {});
    final body = (doc['body'] as List? ?? const []).map((p) => asMaps(p)).toList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Letterhead header + emerald rule
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${header['company']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: HMC.ink, letterSpacing: -0.4)),
              const SizedBox(height: 3),
              Text('${header['addressLine']}', style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500)),
            ]),
          ),
          const SizedBox(width: 10),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: HMC.ink, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text('${header['monogram']}', style: const TextStyle(color: Color(0xFF34D399), fontSize: 15, fontWeight: FontWeight.w900)),
          ),
        ]),
        const SizedBox(height: 12),
        Container(height: 4, color: _emerald500),
        const SizedBox(height: 12),
        // Ref / Dated row
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: '${labels['ref']}', style: TextStyle(fontSize: 11.5, color: _slate700)),
            TextSpan(text: '${doc['ref']}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _slate700)),
          ])),
          Text.rich(TextSpan(children: [
            TextSpan(text: '${labels['dated']}', style: TextStyle(fontSize: 11.5, color: _slate700)),
            TextSpan(text: '${doc['dated']}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _slate700)),
          ])),
        ]),
        const SizedBox(height: 14),
        Text('${doc['addressee']},', style: TextStyle(fontSize: 12.5, height: 1.5, color: _slate700)),
        const SizedBox(height: 20),
        Center(
          child: Text(
            '${doc['title']}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 3.2,
              color: HMC.ink,
              decoration: TextDecoration.underline,
              decorationColor: _emerald500,
              decorationThickness: 2,
            ),
          ),
        ),
        const SizedBox(height: 18),
        ...body.map(
          (para) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text.rich(
              TextSpan(
                children: para
                    .map((seg) => TextSpan(
                          text: '${seg['t']}',
                          style: TextStyle(fontWeight: seg['b'] == true ? FontWeight.w800 : FontWeight.w400),
                        ))
                    .toList(),
              ),
              textAlign: TextAlign.justify,
              style: TextStyle(fontSize: 13.5, height: 1.85, color: _slate800),
            ),
          ),
        ),
        const SizedBox(height: 18),
        // Official seal + signatory
        Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(children: [
            Transform.rotate(
              angle: -12 * math.pi / 180,
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _emerald600.withValues(alpha: 0.7), width: 3)),
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _emerald600.withValues(alpha: 0.5))),
                  alignment: Alignment.center,
                  child: Text(
                    '${labels['stampTop']}\n${labels['stampMid']}\n${labels['stampBottom']}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 6.5, fontWeight: FontWeight.w900, height: 1.25, letterSpacing: 0.6, color: _emerald700),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('${labels['officialSeal']}', style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${labels['forCompany']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _slate700)),
            const SizedBox(height: 34),
            Container(width: 150, height: 1, color: Colors.grey.shade300),
            const SizedBox(height: 3),
            Text('${labels['signatory']}', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.grey.shade500)),
          ]),
        ]),
        const SizedBox(height: 14),
        Container(height: 1, color: Colors.grey.shade100),
        const SizedBox(height: 8),
        Text('${doc['footer']}', textAlign: TextAlign.center, style: TextStyle(fontSize: 8.5, color: Colors.grey.shade400)),
      ]),
    );
  }
}
