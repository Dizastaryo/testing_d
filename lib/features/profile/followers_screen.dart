import 'package:flutter/material.dart';
import 'user_list_screen.dart';

class FollowersScreen extends StatelessWidget {
  final String username;
  const FollowersScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) =>
      UserListScreen(username: username, kind: UserListKind.followers);
}
