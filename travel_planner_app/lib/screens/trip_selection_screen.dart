import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip.dart';
import '../services/api_service.dart';
import 'dashboard_screen.dart';
import 'trip_form_screen.dart';

class TripSelectionScreen extends StatefulWidget {
  const TripSelectionScreen({super.key});

  @override
  State<TripSelectionScreen> createState() => _TripSelectionScreenState();
}

class _TripSelectionScreenState extends State<TripSelectionScreen> {
  List<Trip> _trips = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    try {
      final trips = await ApiService.fetchTrips();
      setState(() {
        _trips = trips;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _selectTrip(Trip trip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_trip_id', trip.id);
    await prefs.setString('selected_trip_name', trip.name);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  Future<void> _createNewTrip() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TripFormScreen(
          onTripCreated: (trip) async {
            await ApiService.addTrip(trip);
            await _selectTrip(trip);
          },
        ),
      ),
    );
    if (result != null) {
      _loadTrips();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Trip'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadTrips,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _trips.isEmpty
                  ? _buildEmptyState()
                  : _buildTripList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewTrip,
        tooltip: 'Create New Trip',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.luggage, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'No trips yet',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Create your first trip to get started'),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createNewTrip,
            icon: const Icon(Icons.add),
            label: const Text('Create Trip'),
          ),
        ],
      ),
    );
  }

  Widget _buildTripList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _trips.length,
      itemBuilder: (context, index) {
        final trip = _trips[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor,
              child: Text(
                trip.name.substring(0, 1).toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(trip.name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${trip.startDate.day}/${trip.startDate.month}/${trip.startDate.year} - ${trip.endDate.day}/${trip.endDate.month}/${trip.endDate.year}',
                ),
                Text(
                  '${trip.initialBudget} ${trip.currency}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
            ),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () => _selectTrip(trip),
          ),
        );
      },
    );
  }
}
