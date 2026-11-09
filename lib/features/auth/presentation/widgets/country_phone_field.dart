import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../../core/tdlib/td_client.dart';
import '../../../../core/theme/glow_colors.dart';
import '../../../../core/widgets/glow_field.dart';

/// Phone entry with a country button: picking a country writes its calling
/// code into the field, and typing a number shows the country it belongs to.
/// Countries come from TDLib (getCountries works before sign-in); an empty
/// field starts with the country TDLib guesses from the connection.
class CountryPhoneField extends StatefulWidget {
  const CountryPhoneField({
    super.key,
    required this.controller,
    this.errorText,
    this.enabled = true,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  State<CountryPhoneField> createState() => _CountryPhoneFieldState();
}

class _CountryPhoneFieldState extends State<CountryPhoneField> {
  late final TdClient _client = context.read<TdClient>();
  List<td.CountryInfo> _countries = const [];
  td.CountryInfo? _country;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list =
          (await _client.invoke<td.Countries>(const td.GetCountries())).countries
              .where((c) => !c.isHidden && c.callingCodes.isNotEmpty)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() => _countries = list);
      if (widget.controller.text.trim().isEmpty) {
        final code = (await _client.invoke<td.Text>(const td.GetCountryCode())).text;
        final guess = list.where((c) => c.countryCode == code).firstOrNull;
        if (guess != null && mounted && widget.controller.text.trim().isEmpty) _pick(guess);
      } else {
        _detect(widget.controller.text);
      }
    } catch (_) {
      // No country list (e.g. a server without it): the field still works.
    }
  }

  void _pick(td.CountryInfo c) {
    final code = c.callingCodes.first;
    final digits = widget.controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    // Keep the number typed so far, minus the previous country's code.
    final old = _country?.callingCodes.firstOrNull;
    final rest = old != null && digits.startsWith(old)
        ? digits.substring(old.length)
        : (digits.isEmpty ? '' : digits);
    final text = '+$code ${rest.trim()}'.trimRight();
    widget.controller.value = TextEditingValue(
      text: rest.isEmpty ? '+$code ' : text,
      selection: TextSelection.collapsed(offset: (rest.isEmpty ? '+$code ' : text).length),
    );
    setState(() => _country = c);
  }

  /// The national trunk 0 typed after the country code (+98 0912…, +44
  /// 07…) makes Telegram call the number invalid; it never belongs there.
  /// Italy is the exception: its 0 is part of the number.
  void _dropTrunkZero() {
    final code = _country?.callingCodes.firstOrNull;
    if (code == null || code == '39') return;
    final text = widget.controller.text;
    final m = RegExp('^\\+$code([\\s-]*)0').firstMatch(text);
    if (m == null) return;
    final fixed = text.replaceRange(m.end - 1, m.end, '');
    widget.controller.value = TextEditingValue(
      text: fixed,
      selection: TextSelection.collapsed(offset: fixed.length),
    );
  }

  void _detect(String text) {
    _dropTrunkZero();
    text = widget.controller.text;
    _debounce?.cancel();
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      if (_country != null) setState(() => _country = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final info = await _client.invoke<td.PhoneNumberInfo>(
          td.GetPhoneNumberInfo(phoneNumberPrefix: digits),
        );
        final country = _visible(info.country, digits);
        if (mounted && country?.countryCode != _country?.countryCode) setState(() => _country = country);
      } catch (_) {}
    });
  }

  /// Telegram's list has hidden pseudo-countries ("CanadaVoIP", anonymous
  /// numbers…) whose codes draw the wrong flag (CanadaVoIP showed France).
  /// The picker leaves them out, so detection does too: the visible country
  /// with the longest matching calling code wins (+1 → United States).
  td.CountryInfo? _visible(td.CountryInfo? found, String digits) {
    if (found == null) return null;
    if (!found.isHidden && _countries.any((c) => c.countryCode == found.countryCode)) return found;
    if (_countries.isEmpty) return found.isHidden ? null : found;
    td.CountryInfo? best;
    var bestLen = 0;
    for (final c in _countries) {
      for (final code in c.callingCodes) {
        final better = code.length > bestLen || (code.length == bestLen && c.countryCode == 'US');
        if (digits.startsWith(code) && better) {
          best = c;
          bestLen = code.length;
        }
      }
    }
    return best;
  }

  Future<void> _choose() async {
    if (_countries.isEmpty) return;
    final picked = await showModalBottomSheet<td.CountryInfo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlowColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CountrySheet(countries: _countries),
    );
    if (picked != null) _pick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = _country;
    // The picker sits inside the field, before the number.
    final picker = Semantics(
      button: true,
      label: c == null ? 'Choose country' : 'Country: ${c.name}',
      child: InkWell(
        onTap: widget.enabled ? _choose : null,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(c?.flagEmoji ?? '🌐', style: const TextStyle(fontSize: 22, height: 1)),
              const Icon(Icons.expand_more_rounded, size: 18, color: GlowColors.textMuted),
              const SizedBox(width: 6),
              Container(width: 1, height: 24, color: GlowColors.outlineStrong.withValues(alpha: 0.6)),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
    return GlowField(
      controller: widget.controller,
      label: c == null ? 'Phone number' : 'Phone number · ${c.name}',
      hint: '+1 555 010 0000',
      keyboardType: TextInputType.phone,
      autofillHints: const [AutofillHints.telephoneNumber],
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s()-]'))],
      errorText: widget.errorText,
      enabled: widget.enabled,
      onChanged: _detect,
      onSubmitted: widget.onSubmitted,
      prefix: picker,
    );
  }
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet({required this.countries});

  final List<td.CountryInfo> countries;

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase().replaceAll('+', '');
    final list = q.isEmpty
        ? widget.countries
        : widget.countries
              .where(
                (c) =>
                    c.name.toLowerCase().contains(q) ||
                    c.englishName.toLowerCase().contains(q) ||
                    c.callingCodes.any((code) => code.startsWith(q)),
              )
              .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search country or code',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: GlowColors.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final c = list[i];
                return ListTile(
                  leading: Text(c.flagEmoji, style: const TextStyle(fontSize: 24)),
                  title: Text(c.name),
                  trailing: Text(
                    '+${c.callingCodes.first}',
                    style: const TextStyle(color: GlowColors.cyan, fontWeight: FontWeight.w600),
                  ),
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
