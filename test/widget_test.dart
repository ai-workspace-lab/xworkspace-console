import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:xworkspace_console/main.dart';

void main() {
  testWidgets('renders workspace shell', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const XWorkspaceApp());

    expect(find.text('XWorkspace'), findsOneWidget);
    expect(find.text('Workspace'), findsWidgets);
    expect(find.text('System healthy'), findsOneWidget);
  });
}
