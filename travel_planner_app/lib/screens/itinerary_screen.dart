import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/api_service.dart';

class ItineraryScreen extends StatefulWidget {
  final Trip? Function() getActiveTrip;
  final ApiService api;
  const ItineraryScreen({super.key, required this.getActiveTrip, required this.api});

  @override
  State<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends State<ItineraryScreen> {
  final _dest = TextEditingController();
  int _days = 3;
  final _budgetLevel = ValueNotifier<String>('mid');
  final _interests = <String>{};
  bool _loading = false;
  List<DayPlan> _plan = [];

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _plan = [];
    });
    try {
      final res = await widget.api.generateItinerary(
        destination: _dest.text.trim(),
        days: _days,
        budgetLevel: _budgetLevel.value,
        interests: _interests.toList(),
      );
      if (!mounted) return;
      setState(() => _plan = res);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.getActiveTrip();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        TextField(
          controller: _dest,
          decoration: InputDecoration(
            labelText: 'Destination',
            hintText: active?.name.contains('Trip') == true
                ? active!.name.replaceAll(' Trip', '')
                : 'Rome',
            prefixIcon: const Icon(Icons.place_outlined),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _days,
                items: [1, 2, 3, 4, 5, 6, 7]
                    .map((d) => DropdownMenuItem(value: d, child: Text('$d days')))
                    .toList(),
                onChanged: (v) => setState(() => _days = v ?? 3),
                decoration: const InputDecoration(labelText: 'Length'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: _budgetLevel,
                builder: (_, val, __) => DropdownButtonFormField<String>(
                  value: val,
                  items: const [
                    DropdownMenuItem(value: 'budget', child: Text('Budget')),
                    DropdownMenuItem(value: 'mid', child: Text('Mid')),
                    DropdownMenuItem(value: 'luxury', child: Text('Luxury')),
                  ],
                  onChanged: (v) => _budgetLevel.value = v ?? val,
                  decoration: const InputDecoration(labelText: 'Budget'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _InterestChips(
          initial: const [
            'Food',
            'Museums',
            'Outdoors',
            'Nightlife',
            'History',
            'Shopping'
          ],
          onChange: (set) => _interests
            ..clear()
            ..addAll(set),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loading ? null : _generate,
          icon: const Icon(Icons.auto_awesome),
          label: Text(_loading ? 'Generating...' : 'Generate itinerary'),
        ),
        const SizedBox(height: 16),
        for (final day in _plan)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Day ${day.day}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  ...day.items.map(
                    (it) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(it)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _InterestChips extends StatefulWidget {
  final List<String> initial;
  final void Function(Set<String>) onChange;
  const _InterestChips({required this.initial, required this.onChange, super.key});

  @override
  State<_InterestChips> createState() => _InterestChipsState();
}

class _InterestChipsState extends State<_InterestChips> {
  late Set<String> selected;
  @override
  void initState() {
    super.initState();
    selected = {};
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.initial.map((label) {
        final on = selected.contains(label);
        return FilterChip(
          label: Text(label),
          selected: on,
          onSelected: (v) {
            setState(() {
              if (v) {
                selected.add(label);
              } else {
                selected.remove(label);
              }
              widget.onChange(selected);
            });
          },
        );
      }).toList(),
    );
  }
}

