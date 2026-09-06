import 'package:flutter/material.dart';

import 'app.dart';
import 'data/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    runApp(ReMagyarApp(store: await CardStore.open()));
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Не удалось открыть банк слов. Перезапустите приложение.',
            ),
          ),
        ),
      ),
    );
  }
}
