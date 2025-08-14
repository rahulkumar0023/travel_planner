import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/api_service.dart';

class TripFormScreen extends StatefulWidget {
  const TripFormScreen({super.key});
  @override
  State<TripFormScreen> createState() => _TripFormScreenState();
}

class _TripFormScreenState extends State<TripFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  final _currency = ValueNotifier<String>('EUR');
  final _participants = <String>[];
  final _participantCtrl = TextEditingController();
  bool _submitting = false;

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _start = picked;
        } else {
          _end = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_start == null || _end == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick start and end dates')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final created = await ApiService.addTrip(
        Trip(
          id: 'temp', // backend will assign
          name: _name.text.trim(),
          startDate: _start!,
          endDate: _end!,
          initialBudget: 0,
          currency: _currency.value,
          participants: _participants,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop<Trip>(created);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Create failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New trip')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Trip name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(_start == null
                        ? 'Start date'
                        : _start!.toString().split(' ').first),
                    onPressed: () => _pickDate(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month),
                    label: Text(_end == null
                        ? 'End date'
                        : _end!.toString().split(' ').first),
                    onPressed: () => _pickDate(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
              valueListenable: _currency,
              builder: (_, cur, __) {
                return DropdownButtonFormField<String>(
                  value: cur,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: const ['EUR', 'USD', 'GBP', 'INR']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => _currency.value = v ?? cur,
                );
              },
            ),
            const SizedBox(height: 16),
            Text('Participants',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _participants)
                  Chip(
                      label: Text(p),
                      onDeleted: () => setState(() => _participants.remove(p))),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _participantCtrl,
                    decoration: InputDecoration(
                      hintText: 'Add name',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          final v = _participantCtrl.text.trim();
                          if (v.isNotEmpty && !_participants.contains(v)) {
                            setState(() => _participants.add(v));
                            _participantCtrl.clear();
                          }
                        },
                      ),
                    ),
                    onSubmitted: (_) {
                      final v = _participantCtrl.text.trim();
                      if (v.isNotEmpty && !_participants.contains(v)) {
                        setState(() => _participants.add(v));
                        _participantCtrl.clear();
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: const Icon(Icons.check),
              label:
                  Text(_submitting ? 'Creating...' : 'Create trip'),
            ),
          ],
        ),
      ),
    );
  }
}

