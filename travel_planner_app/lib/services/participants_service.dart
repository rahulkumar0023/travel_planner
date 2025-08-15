import 'package:flutter/foundation.dart';
import 'dart:collection';

class ParticipantsService with ChangeNotifier {
  List<String> _participants = [];

  UnmodifiableListView<String> get participants =>
      UnmodifiableListView(_participants);

  Future<void> add(String name) async {
    _participants = [..._participants, name];
    notifyListeners();
  }

  Future<void> remove(String name) async {
    _participants = _participants.where((p) => p != name).toList();
    notifyListeners();
  }
}

final participantsService = ParticipantsService();
