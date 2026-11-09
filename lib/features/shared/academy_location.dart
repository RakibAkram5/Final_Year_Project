import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../data/models/app_user.dart';
import '../../data/remote/api_client.dart';
import '../../logic/auth_provider.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/gradient_background.dart';

/// OpenStreetMap tiles. Free for light use under the OSM tile policy, which
/// requires attribution (shown on every map) and an identifying app id.
const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgentPackage = 'com.taleemplus.app';

/// Default view (Pakistan) until a location is chosen.
const _fallbackCenter = LatLng(30.3753, 69.3451);

Future<void> _launch(BuildContext context, Uri uri) async {
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the maps application.')));
  }
}

class _MapView extends StatelessWidget {
  final LatLng? pin;
  final bool interactive;
  final MapController? controller;
  final void Function(LatLng)? onTap;

  const _MapView(
      {this.pin, this.interactive = false, this.controller, this.onTap});

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: pin ?? _fallbackCenter,
        initialZoom: pin == null ? 5 : 16,
        interactionOptions: InteractionOptions(
            flags: interactive ? InteractiveFlag.all : InteractiveFlag.none),
        onTap: onTap == null ? null : (_, point) => onTap!(point),
      ),
      children: [
        TileLayer(
          urlTemplate: _tileUrl,
          userAgentPackageName: _userAgentPackage,
          maxZoom: 19,
        ),
        if (pin != null)
          MarkerLayer(markers: [
            Marker(
              point: pin!,
              width: 44,
              height: 44,
              alignment: Alignment.topCenter,
              child: const Icon(Icons.location_on_rounded,
                  size: 44, color: AppColors.danger),
            ),
          ]),
        // Required OSM attribution. A plain wrapping label: the package's
        // attribution row overflows on very small maps.
        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            color: Colors.white.withValues(alpha: 0.85),
            child: const Text('© OpenStreetMap contributors',
                style: TextStyle(fontSize: 10, color: Colors.black87)),
          ),
        ),
      ],
    );
  }
}

/// Read-only academy location for every portal: map, address and buttons
/// to open directions. Shows an explicit message when no location is saved
/// (never a made-up location).
class AcademyLocationCard extends StatelessWidget {
  final AppUser? user;
  final bool showEditHint;
  const AcademyLocationCard({super.key, this.user, this.showEditHint = false});

  @override
  Widget build(BuildContext context) {
    final u = user ?? context.watch<AuthProvider>().currentUser;
    final loc = u?.academyLocation;
    final colors = context.appColors;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loc != null)
            SizedBox(
              height: 180,
              child: Semantics(
                label: 'Map showing the academy location',
                child: _MapView(pin: LatLng(loc.latitude, loc.longitude)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u?.academyName ?? 'Academy',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                const SizedBox(height: 4),
                if ((u?.academyAddress ?? '').isNotEmpty)
                  Text(u!.academyAddress!,
                      style: TextStyle(color: colors.textSecondary)),
                if (loc?.label != null && loc!.label != u?.academyAddress)
                  Text(loc.label!,
                      style: TextStyle(color: colors.textMuted, fontSize: 12)),
                if (loc == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        showEditHint
                            ? 'No map location saved yet. Set it so parents and students can get directions.'
                            : 'The academy has not added its map location yet.',
                        style:
                            TextStyle(color: colors.textMuted, fontSize: 12)),
                  )
                else ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.icon(
                      onPressed: () => _launch(context, loc.directionsUri),
                      icon: const Icon(Icons.directions_rounded),
                      label: const Text('Directions'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.textOnAccent),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _launch(context, loc.openStreetMapUri),
                      icon: const Icon(Icons.map_rounded),
                      label: const Text('Open map'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.accent,
                          side: const BorderSide(color: AppColors.accent)),
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Place {
  final String label;
  final LatLng point;
  _Place(this.label, this.point);
}

/// Admin screen to set the academy address and map location: search an
/// address, tap the map to adjust the pin, or use the device's position.
class AcademyLocationEditorScreen extends StatefulWidget {
  const AcademyLocationEditorScreen({super.key});

  @override
  State<AcademyLocationEditorScreen> createState() =>
      _AcademyLocationEditorScreenState();
}

class _AcademyLocationEditorScreenState
    extends State<AcademyLocationEditorScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  late final TextEditingController _address;
  LatLng? _pin;
  String? _label;
  List<_Place> _results = const [];
  bool _searching = false;
  bool _locating = false;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthProvider>().currentUser;
    _address = TextEditingController(text: u?.academyAddress ?? '');
    final loc = u?.academyLocation;
    if (loc != null) {
      _pin = LatLng(loc.latitude, loc.longitude);
      _label = loc.label;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _address.dispose();
    super.dispose();
  }

  void _setPin(LatLng p, {String? label, bool move = true}) {
    setState(() {
      _pin = p;
      _label = label;
      _results = const [];
    });
    if (move) _map.move(p, 17);
  }

  Future<void> _doSearch() async {
    final q = _search.text.trim();
    if (q.length < 3) {
      setState(() => _message = 'Type at least 3 characters to search.');
      return;
    }
    setState(() {
      _searching = true;
      _message = null;
    });
    try {
      final res =
          await ApiClient().get('/geo/search?q=${Uri.encodeQueryComponent(q)}');
      final places = (res as List)
          .map((e) => _Place(
              e['label'].toString(),
              LatLng((e['latitude'] as num).toDouble(),
                  (e['longitude'] as num).toDouble())))
          .toList();
      setState(() {
        _results = places;
        if (places.isEmpty) {
          _message = 'No matches. Try a nearby landmark or tap the map.';
        }
      });
    } catch (e) {
      setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _useCurrentPosition() async {
    setState(() {
      _locating = true;
      _message = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Location services are turned off on this device.';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        throw 'Location permission was denied. Search for the address or tap the map instead.';
      }
      if (perm == LocationPermission.deniedForever) {
        throw 'Location permission is blocked. Enable it in system settings, '
            'or search for the address instead.';
      }
      final pos = await Geolocator.getCurrentPosition(
              locationSettings:
                  const LocationSettings(accuracy: LocationAccuracy.high))
          .timeout(const Duration(seconds: 20));
      _setPin(LatLng(pos.latitude, pos.longitude),
          label: 'Device location (±${pos.accuracy.round()} m)');
    } on TimeoutException {
      setState(() => _message = 'Could not get a GPS fix. Try again outdoors '
          'or set the pin on the map.');
    } catch (e) {
      setState(() => _message = '$e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save({bool remove = false}) async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await context.read<AuthProvider>().saveAcademyLocation(
            remove || _pin == null
                ? null
                : AcademyLocation(_pin!.latitude, _pin!.longitude,
                    label: _label),
            address: _address.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(remove ? 'Location removed' : 'Location saved'),
            backgroundColor: AppColors.success));
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _message = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hadLocation =
        context.read<AuthProvider>().currentUser?.academyLocation != null;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Academy location',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: GradientBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  LabeledField(
                      label: 'Street address',
                      hint: 'Shown to parents and students',
                      controller: _address),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _doSearch(),
                        decoration: const InputDecoration(
                            labelText: 'Search address or landmark',
                            prefixIcon: Icon(Icons.search_rounded)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _searching
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.accent))
                        : IconButton(
                            tooltip: 'Search',
                            onPressed: _doSearch,
                            icon: Icon(Icons.arrow_forward_rounded,
                                color: context.appColors.accentText)),
                  ]),
                  for (final p in _results)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.place_outlined,
                          color: context.appColors.accentText),
                      title: Text(p.label, maxLines: 2),
                      onTap: () => _setPin(p.point, label: p.label),
                    ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 320,
                      child: _MapView(
                        pin: _pin,
                        interactive: true,
                        controller: _map,
                        onTap: (p) =>
                            _setPin(p, label: 'Pin placed on map', move: false),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                      _pin == null
                          ? 'Tap the map, search, or use your position to place the pin.'
                          : 'Pin: ${_pin!.latitude.toStringAsFixed(6)}, ${_pin!.longitude.toStringAsFixed(6)}'
                              '${_label == null ? '' : ' · $_label'}',
                      style: TextStyle(color: colors.textMuted, fontSize: 12)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _locating ? null : _useCurrentPosition,
                      icon: _locating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location_rounded),
                      label: const Text('Use my current position'),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.accent),
                    ),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_message!,
                          style: const TextStyle(color: AppColors.danger)),
                    ),
                  const SizedBox(height: 8),
                  PrimaryButton(
                    label: 'Save location',
                    icon: Icons.check_rounded,
                    loading: _saving,
                    onPressed: _saving || _pin == null ? null : () => _save(),
                  ),
                  if (hadLocation)
                    TextButton(
                      onPressed: _saving ? null : () => _save(remove: true),
                      child: const Text('Remove saved location',
                          style: TextStyle(color: AppColors.danger)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen academy location for students and teachers.
class AcademyLocationScreen extends StatelessWidget {
  const AcademyLocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Academy location',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: GradientBackground(
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: const AcademyLocationCard(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
