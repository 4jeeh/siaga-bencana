import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(key: const Key('zone-search-query'), controller: _query,
        decoration: const InputDecoration(labelText: 'Cari provinsi, kota, atau kecamatan'),
        textInputAction: TextInputAction.search, onSubmitted: (_) => _search(),
        onChanged: (_) => setState(() => _showResults = false)),
      TextButton(key: const Key('zone-search-btn'), onPressed: _search, child: const Text('Cari')),
      if (_showResults) ...[
        if (vm.searchingLocations) const LinearProgressIndicator(),
        if (vm.locationSearchError != null) Text(vm.locationSearchError!),
        for (final item in vm.locationResults)
          ListTile(title: Text(item.label), subtitle: Text(item.subtitle),
            onTap: vm.busy ? null : () {
              setState(() => _showResults = false);
              widget.onSelected(item);
            }),
      ],
    ]);
  }
}
