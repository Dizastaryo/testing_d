import 'package:flutter/foundation.dart';
import '../data/mock_users.dart';

class AccountSession extends ChangeNotifier {
  MockUser _current;

  AccountSession._(this._current);

  static final AccountSession instance = AccountSession._(user005);

  MockUser get currentUser => _current;
  List<String> get friendIds => _current.friendIds;

  void switchTo(MockUser user) {
    _current = user;
    notifyListeners();
  }
}
