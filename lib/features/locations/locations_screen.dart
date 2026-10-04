import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/app_scope.dart';
import '../../core/json_helpers.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class LocationsScreen extends StatefulWidget {
  const LocationsScreen({super.key});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  List<Map<String, dynamic>> _locations = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await AppScope.of(context).api.get('locations');
      if (mounted) setState(() => _locations = asJsonList(asJsonMap(response)['items']));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([Map<String, dynamic>? location]) async {
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _LocationFormDialog(location: location),
    );
    if (values == null || !mounted) return;
    try {
      final api = AppScope.of(context).api;
      if (location == null) {
        await api.post('locations', values);
      } else {
        await api.patch('locations/${location['id']}', values);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(location == null ? 'Work location created.' : 'Work location updated.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _deactivate(Map<String, dynamic> location) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Disable this location?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('New punches will no longer be accepted here. Existing open shifts can still punch out at their assigned site.', style: TextStyle(color: AppColors.muted, height: 1.45)),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC94D54)), child: const Text('Disable'))],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AppScope.of(context).api.delete('locations/${location['id']}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Work location disabled.')));
      await _load();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).user!;
    final canCreate = user.can('locations.create');
    final canUpdate = user.can('locations.update');
    final canDelete = user.can('locations.delete');
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1270),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageHeading(
                  title: 'Work locations',
                  subtitle: 'Define where a verified attendance punch can happen.',
                  trailing: canCreate ? PrimaryButton(label: 'Add location', icon: Icons.add_location_alt_outlined, onPressed: () => _openForm()) : null,
                ),
                Container(
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFDDE9FC))),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.gps_fixed_rounded, color: AppColors.blue, size: 20), SizedBox(width: 11), Expanded(child: Text('Each active location has a GPS center and radius. The API calculates the distance and rejects punches outside the nearest enabled geofence.', style: TextStyle(color: AppColors.ink, fontSize: 12, height: 1.5)))]),
                ),
                const SizedBox(height: 17),
                if (_loading && _locations.isEmpty)
                  const SizedBox(height: 200, child: LoadingView(label: 'Loading work locations…'))
                else if (_error != null && _locations.isEmpty)
                  ErrorNotice(message: _error!, onRetry: _load)
                else if (_locations.isEmpty)
                  const AppPanel(child: EmptyNotice(title: 'No locations yet', subtitle: 'Create a work site and set its geofence radius.', icon: Icons.location_off_outlined))
                else
                  LayoutBuilder(builder: (context, constraints) {
                    final count = constraints.maxWidth >= 1000 ? 3 : constraints.maxWidth >= 610 ? 2 : 1;
                    const gap = 15.0;
                    final width = (constraints.maxWidth - gap * (count - 1)) / count;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: _locations.map((location) => SizedBox(width: width, child: _LocationCard(location: location, canUpdate: canUpdate, canDelete: canDelete, onEdit: () => _openForm(location), onDeactivate: () => _deactivate(location)))).toList(),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.location, required this.canUpdate, required this.canDelete, required this.onEdit, required this.onDeactivate});
  final Map<String, dynamic> location;
  final bool canUpdate;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final active = location['is_active'] == true || location['is_active'] == 1;
    return AppPanel(
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: AppColors.softBlue, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.location_on_rounded, color: AppColors.blue, size: 21)), const SizedBox(width: 12), Expanded(child: Text(stringValue(location['name']), style: const TextStyle(color: AppColors.ink, fontSize: 15, fontWeight: FontWeight.w800))), StatusBadge(status: active ? 'active' : 'inactive')]),
          const SizedBox(height: 15),
          Text(stringValue(location['address']), style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)),
          const SizedBox(height: 17),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF6F9FC), borderRadius: BorderRadius.circular(13)),
            child: Column(children: [
              _LocationDetail(icon: Icons.radar_rounded, label: 'Geofence radius', value: '${stringValue(location['radius_m'])} m'),
              const SizedBox(height: 9),
              _LocationDetail(icon: Icons.my_location_rounded, label: 'Center coordinates', value: '${_coordinate(location['latitude'])}, ${_coordinate(location['longitude'])}'),
              const SizedBox(height: 9),
              _LocationDetail(icon: Icons.public_rounded, label: 'Timezone', value: stringValue(location['timezone'], fallback: 'UTC')),
            ]),
          ),
          if (canUpdate || (canDelete && active)) ...[
            const SizedBox(height: 15),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (canDelete && active) TextButton.icon(onPressed: onDeactivate, style: TextButton.styleFrom(foregroundColor: const Color(0xFFC94D54)), icon: const Icon(Icons.location_off_outlined, size: 17), label: const Text('Disable')),
              if (canUpdate) ...[
                if (canDelete && active) const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: onEdit, icon: const Icon(Icons.tune_rounded, size: 17), label: const Text('Edit geofence')),
              ],
            ]),
          ],
        ],
      ),
    );
  }
}

class _LocationDetail extends StatelessWidget {
  const _LocationDetail({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, color: AppColors.muted, size: 16), const SizedBox(width: 8), Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11))), Text(value, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700, fontSize: 11))]);
}

class _LocationFormDialog extends StatefulWidget {
  const _LocationFormDialog({this.location});
  final Map<String, dynamic>? location;

  @override
  State<_LocationFormDialog> createState() => _LocationFormDialogState();
}

class _LocationFormDialogState extends State<_LocationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  late final TextEditingController _radius;
  late final TextEditingController _timezone;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final location = widget.location ?? const <String, dynamic>{};
    _name = TextEditingController(text: stringValue(location['name']));
    _address = TextEditingController(text: stringValue(location['address']));
    _latitude = TextEditingController(text: stringValue(location['latitude']));
    _longitude = TextEditingController(text: stringValue(location['longitude']));
    _radius = TextEditingController(text: stringValue(location['radius_m'], fallback: '150'));
    _timezone = TextEditingController(text: stringValue(location['timezone'], fallback: 'UTC'));
    _active = location['is_active'] == null ? true : location['is_active'] == true || location['is_active'] == 1;
  }

  @override
  void dispose() {
    for (final controller in [_name, _address, _latitude, _longitude, _radius, _timezone]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, <String, dynamic>{
      'name': _name.text.trim(),
      'address': _address.text.trim(),
      'latitude': double.parse(_latitude.text.trim()),
      'longitude': double.parse(_longitude.text.trim()),
      'radius_m': int.parse(_radius.text.trim()),
      'timezone': _timezone.text.trim(),
      'is_active': _active,
    });
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.location != null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
      title: Text(editing ? 'Edit work location' : 'Add work location', style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(children: [
              _field('Location name', _name),
              _field('Street address', _address),
              Row(children: [Expanded(child: _field('Latitude', _latitude, numeric: true)), const SizedBox(width: 12), Expanded(child: _field('Longitude', _longitude, numeric: true))]),
              Row(children: [Expanded(child: _field('Radius in metres', _radius, numeric: true, integer: true)), const SizedBox(width: 12), Expanded(child: _field('Timezone', _timezone))]),
              SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _active, activeColor: AppColors.success, title: const Text('Location active', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), subtitle: const Text('Only active sites accept punches.', style: TextStyle(fontSize: 11, color: AppColors.muted)), onChanged: (value) => setState(() => _active = value)),
            ]),
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), ElevatedButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded, size: 17), label: Text(editing ? 'Save location' : 'Create location'))],
    );
  }

  Widget _field(String label, TextEditingController controller, {bool numeric = false, bool integer = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: TextFormField(
        controller: controller,
        keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true, signed: true) : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (text.isEmpty) return 'Required';
          if (numeric && (integer ? int.tryParse(text) == null : double.tryParse(text) == null)) return 'Enter a number';
          if (label == 'Latitude') {
            final number = double.tryParse(text);
            if (number == null || number < -90 || number > 90) return 'Use −90 to 90';
          }
          if (label == 'Longitude') {
            final number = double.tryParse(text);
            if (number == null || number < -180 || number > 180) return 'Use −180 to 180';
          }
          if (label == 'Radius in metres' && (int.tryParse(text) ?? 0) < 1) return 'Must be over 0';
          return null;
        },
      ),
    );
  }
}

String _coordinate(Object? value) {
  final number = double.tryParse(stringValue(value));
  return number == null ? '—' : number.toStringAsFixed(4);
}
