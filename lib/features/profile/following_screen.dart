import 'package:flutter/material.dart';
import 'user_list_screen.dart';

class FollowingScreen extends StatelessWidget {
  final String username;
  const FollowingScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) =>
      UserListScreen(username: username, kind: UserListKind.following);
}
