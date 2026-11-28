import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import 'zone_dto.dart';
import 'zone_view_model.dart';

class LocationSearchField extends StatefulWidget {
  const LocationSearchField({super.key, required this.onSelected});
  final ValueChanged<LocationSuggestionDto> onSelected;

  @override
  State<LocationSearchField> createState() => _LocationSearchFieldState();
}

class _LocationSearchFieldState extends State<LocationSearchField> {
  final _query = TextEditingController();
  bool _showResults = false;

  void _search() {
    FocusScope.of(context).unfocus();
    setState(() => _showResults = true);
    context.read<ZoneViewModel>().searchLocations(_query.text);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ZoneViewModel>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('zone-search-query'),
          controller: _query,
          decoration: InputDecoration(
            labelText: 'Cari kota atau kecamatan',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              key: const Key('zone-search-btn'),
              tooltip: 'Cari',
              onPressed: _search,
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          onChanged: (_) => setState(() => _showResults = false),
        ),
        if (_showResults) ...[
          const SizedBox(height: AppSpace.s),
          if (vm.searchingLocations) const LinearProgressIndicator(),
          if (vm.locationSearchError != null)
            Semantics(liveRegion: true, child: Text(vm.locationSearchError!)),
          if (vm.locationResults.isNotEmpty)
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in vm.locationResults)
                    ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(item.label),
                      subtitle: Text(item.subtitle),
                      onTap: vm.busy
                          ? null
                          : () {
                              setState(() => _showResults = false);
                              widget.onSelected(item);
                            },
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
