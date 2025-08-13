import 'package:flutter/material.dart';
import '../models/trip.dart';

class TripFormScreen extends StatefulWidget {
  final Function(Trip) onTripCreated;

  TripFormScreen({required this.onTripCreated});

  @override
  State<TripFormScreen> createState() => _TripFormScreenState();
}

class _TripFormScreenState extends State<TripFormScreen> {
  final _nameController = TextEditingController();
  final _budgetController = TextEditingController();
  final _currencyController = TextEditingController(text: 'EUR');

  void _submitForm() {
    final trip = Trip(
      id: DateTime.now().toString(),
      name: _nameController.text,
      startDate: DateTime.now(),
      endDate: DateTime.now().add(Duration(days: 5)),
      initialBudget: double.parse(_budgetController.text),
      currency: _currencyController.text,
      participants: ['Rahul', 'Alex'], // static for now
    );

    widget.onTripCreated(trip);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('New Trip')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: InputDecoration(labelText: 'Trip Name'),
            ),
            TextField(
              controller: _budgetController,
              decoration: InputDecoration(labelText: 'Budget'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _currencyController,
              decoration: InputDecoration(labelText: 'Currency'),
            ),
            SizedBox(height: 20),
            ElevatedButton(onPressed: _submitForm, child: Text('Create Trip')),
          ],
        ),
      ),
    );
  }
}
