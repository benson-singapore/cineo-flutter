import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cineo_flutter/data/hub/hub_sync_api.dart';
import 'package:cineo_flutter/features/search/phone_search_assist.dart';

class FakeCredentials extends HubDeviceCredentials {
  FakeCredentials(this.bound);
  final bool bound;
  @override
  Future<bool> get isBound async => bound;
}

class FakeApi extends HubSyncApi {
  FakeApi({bool bound = true, this.sessions = const [], this.fail = false})
      : super(credentials: FakeCredentials(bound));
  final List<Map<String, Object?>> sessions;
  final bool fail;
  String? submitted;
  int checks = 0;

  @override
  Future<Map<String, Object?>> inputSessions() async {
    checks++;
    if (fail) throw const HubApiException(50000, 'Hub 暂时不可用');
    return {'sessions': sessions};
  }

  @override
  Future<Map<String, Object?>> submitInput(String id, String text) async {
    submitted = '$id:$text';
    return {};
  }
}

void main() {
  Future<void> open(WidgetTester tester, FakeApi api) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showManualPhoneSearchAssist(context, api),
        child: const Text('打开'),
      ),
    ))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('未绑定时提示绑定且不查询', (tester) async {
    final api = FakeApi(bound: false);
    await open(tester, api);
    expect(find.textContaining('手机尚未绑定'), findsOneWidget);
    expect(api.checks, 0);
  });

  testWidgets('无会话可重新检查', (tester) async {
    final api = FakeApi();
    await open(tester, api);
    expect(find.textContaining('当前没有可用'), findsOneWidget);
    await tester.tap(find.text('重新检查'));
    await tester.pumpAndSettle();
    expect(api.checks, 2);
  });

  testWidgets('网络失败给出反馈', (tester) async {
    await open(tester, FakeApi(fail: true));
    expect(find.textContaining('Hub 暂时不可用'), findsOneWidget);
  });

  testWidgets('选择电视并提交文本', (tester) async {
    final api = FakeApi(sessions: [
      {
        'id': 'tv1',
        'tv_name': '客厅电视',
        'expires_at': DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch
      },
      {
        'id': 'tv2',
        'tv_name': '卧室电视',
        'expires_at': DateTime.now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch
      },
    ]);
    await open(tester, api);
    await tester.tap(find.text('卧室电视'));
    await tester.enterText(find.byType(TextField), '电影');
    await tester.tap(find.text('发送到电视'));
    await tester.pumpAndSettle();
    expect(api.submitted, 'tv2:电影');
    expect(find.textContaining('已发送到电视'), findsOneWidget);
  });
}
