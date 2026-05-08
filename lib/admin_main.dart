// Entry point for the admin web bundle. Build with:
//   flutter build web --release \
//       --target=lib/admin_main.dart \
//       -o build/admin \
//       --dart-define=API_BASE_URL=https://api.seeu.kz/api/v1
//
// Deploy build/admin to admin.seeu.kz.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/admin/admin_app.dart';

void main() {
  runApp(const ProviderScope(child: AdminApp()));
}
