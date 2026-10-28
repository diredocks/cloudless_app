import 'dart:async';
import 'dart:convert';

import 'package:cloudless_app/data/local/cities_store.dart';
import 'package:cloudless_app/data/local/settings_store.dart';
import 'package:cloudless_app/main.dart';
import 'package:cloudless_app/models/city.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures.dart';
import 'helpers.dart';

void main() {
  MockClient okClient() =>
      MockClient((request) async => http.Response(sampleWeatherResponse, 200));

  /// Answers the area-search endpoint with Chinese cities and the weather
  /// endpoint with the sample payload.
  MockClient routingClient() => MockClient((request) async {
    if (request.url.host == 'decision-admin.tianqi.cn') {
      return http.Response.bytes(utf8.encode(sampleCitySearchResponse), 200);
    }
    return http.Response(sampleWeatherResponse, 200);
  });

  Widget appWith(
    SettingsStore settingsStore, {
    CitiesStore? citiesStore,
    http.Client? client,
  }) => CloudlessApp(
    settingsStore: settingsStore,
    citiesStore: citiesStore ?? MemoryCitiesStore(),
    client: client ?? okClient(),
  );

  Widget app({String? apiKey, String? languageCode, http.Client? client}) =>
      appWith(MemorySettingsStore(apiKey, languageCode), client: client);

  testWidgets('renders the current weather fetched from the API', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(apiKey: 'test-key'));
    await tester.pumpAndSettle();

    expect(find.text('北京'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(
      find.text('Over the next two hours, no rain is expected'),
      findsOneWidget,
    );
  });

  testWidgets('can switch to the weekly tab', (WidgetTester tester) async {
    await tester.pumpWidget(app(apiKey: 'test-key'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('weekly'));
    await tester.pumpAndSettle();

    expect(find.text('mostly sunny for the next 7 days'), findsOneWidget);
    expect(find.text('wednesday'), findsOneWidget);
  });

  testWidgets('can switch to the hourly tab', (WidgetTester tester) async {
    await tester.pumpWidget(app(apiKey: 'test-key'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('hourly'));
    await tester.pumpAndSettle();

    expect(find.text('mostly sunny for the next 24 hours'), findsOneWidget);
    expect(find.text('9 pm'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('toggling the hour format updates the hourly tab', (
    WidgetTester tester,
  ) async {
    final store = MemorySettingsStore('test-key');
    await tester.pumpWidget(appWith(store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('hourly'));
    await tester.pumpAndSettle();
    expect(find.text('9 pm'), findsOneWidget);

    await tester.longPress(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(store.settings.use24Hour, isTrue);
    expect(find.text('21:00'), findsOneWidget);
    expect(find.text('9 pm'), findsNothing);
  });

  testWidgets('switching city from search returns to today', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(apiKey: 'test-key'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('search'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('广州'));
    await tester.pumpAndSettle();

    expect(find.text('广州'), findsOneWidget);
    expect(find.text('北京'), findsNothing);
  });

  testWidgets('shows a spinner while the request is in flight', (
    WidgetTester tester,
  ) async {
    final pending = MockClient((request) => Completer<http.Response>().future);
    await tester.pumpWidget(app(apiKey: 'test-key', client: pending));
    await tester.pump();

    expect(find.text('loading weather\u2026'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows a retry action when the request fails', (
    WidgetTester tester,
  ) async {
    final failing = MockClient((request) async => http.Response('boom', 500));
    await tester.pumpWidget(app(apiKey: 'test-key', client: failing));
    await tester.pumpAndSettle();

    expect(find.text('try again'), findsOneWidget);
    expect(find.text('the weather service returned 500'), findsOneWidget);
  });

  testWidgets('asks for an API key on first launch', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(apiKey: null));
    await tester.pumpAndSettle();

    expect(find.text('finish setting up'), findsOneWidget);
    expect(
      find.text('enter your API key and choose a language'),
      findsOneWidget,
    );
    expect(find.text('北京'), findsNothing);
  });

  testWidgets('entering a valid key on first launch opens the app', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(apiKey: null));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'test-key');
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(find.text('北京'), findsOneWidget);
  });

  testWidgets('tapping settings shows a hint, long press opens settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(apiKey: 'test-key'));
    await tester.pumpAndSettle();

    final hintOpacity = find.ancestor(
      of: find.text('long press to open settings'),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(hintOpacity).opacity, 0);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('long press to open settings'), findsOneWidget);
    expect(tester.widget<Opacity>(hintOpacity).opacity, 1);

    await tester.longPress(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    expect(find.text('API key'), findsOneWidget);

    // Let the hint animation finish so it fades out.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('saving a new key from settings persists it', (
    WidgetTester tester,
  ) async {
    final store = MemorySettingsStore('old-key');
    await tester.pumpWidget(appWith(store));
    await tester.pumpAndSettle();

    await tester.longPress(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'new-key');
    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(store.settings.apiKey, 'new-key');
    expect(find.text('北京'), findsOneWidget);
  });

  testWidgets('renders Simplified Chinese when selected', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(app(apiKey: 'test-key', languageCode: 'zh'));
    await tester.pumpAndSettle();

    expect(find.text('北京'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('体感温度'), findsOneWidget);

    await tester.tap(find.text('一周'));
    await tester.pumpAndSettle();

    expect(find.text('未来 7 天以晴为主'), findsOneWidget);
    expect(find.text('周三'), findsOneWidget);
  });

  testWidgets('changing the language is only persisted when saved', (
    WidgetTester tester,
  ) async {
    final store = MemorySettingsStore('test-key');
    await tester.pumpWidget(appWith(store));
    await tester.pumpAndSettle();

    await tester.longPress(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('简体中文').last);
    await tester.pumpAndSettle();

    // Selecting a language must not persist or apply it yet.
    expect(store.settings.languageCode, isNull);
    expect(find.text('设置'), findsNothing);

    await tester.tap(find.text('save'));
    await tester.pumpAndSettle();

    expect(store.settings.languageCode, 'zh');
    expect(find.text('今天'), findsOneWidget);
  });

  testWidgets('searches and adds a city from the results', (
    WidgetTester tester,
  ) async {
    final cities = MemoryCitiesStore();
    await tester.pumpWidget(
      appWith(
        MemorySettingsStore('test-key'),
        citiesStore: cities,
        client: routingClient(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('search'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '北京');
    // Build once so the debounced search provider starts, then let it elapse.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('北京，海淀'), findsOneWidget);

    await tester.tap(find.text('北京，海淀'));
    await tester.pumpAndSettle();

    expect(cities.cityList.cities.any((c) => c.id == '101010200'), isTrue);

    // Let the confirmation SnackBar time out so no timer outlives the test.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('a slow search cannot overwrite a newer one', (
    WidgetTester tester,
  ) async {
    // The earlier query answers late; the newer one answers immediately.
    const slowResponse =
        '[{"city":"测试城","dis":"测试城","pro":"测试省","cid":"999999999","lat":"1.0","lng":"2.0"}]';
    final client = MockClient((request) async {
      if (request.url.host == 'decision-admin.tianqi.cn') {
        if (request.url.queryParameters['key'] == '北京') {
          return http.Response.bytes(
            utf8.encode(sampleCitySearchResponse),
            200,
          );
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        return http.Response.bytes(utf8.encode(slowResponse), 200);
      }
      return http.Response(sampleWeatherResponse, 200);
    });

    await tester.pumpWidget(
      appWith(MemorySettingsStore('test-key'), client: client),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('search'));
    await tester.pumpAndSettle();

    // First query: the debounce elapses and the slow request goes in flight.
    await tester.enterText(find.byType(TextField), '北');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Second query replaces it and resolves quickly.
    await tester.enterText(find.byType(TextField), '北京');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('北京，海淀'), findsOneWidget);

    // The stale first response finally arrives; it must not replace the view.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('北京，海淀'), findsOneWidget);
    expect(find.text('测试省，测试城'), findsNothing);
  });

  testWidgets('removes a city from the list', (WidgetTester tester) async {
    final cities = MemoryCitiesStore();
    await tester.pumpWidget(
      appWith(
        MemorySettingsStore('test-key'),
        citiesStore: cities,
        client: routingClient(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('search'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('北京'));
    await tester.pumpAndSettle();

    expect(find.text('remove city'), findsOneWidget);
    expect(find.text('remove 北京?'), findsOneWidget);

    await tester.tap(find.text('delete'));
    await tester.pumpAndSettle();

    expect(cities.cityList.cities, hasLength(cityCatalog.length - 1));
    expect(cities.cityList.cities.any((c) => c.id == '101010100'), isFalse);
  });

  testWidgets('pull to refresh reloads the weather', (
    WidgetTester tester,
  ) async {
    var weatherRequests = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'decision-admin.tianqi.cn') {
        return http.Response.bytes(utf8.encode(sampleCitySearchResponse), 200);
      }
      weatherRequests++;
      return http.Response(sampleWeatherResponse, 200);
    });

    await tester.pumpWidget(
      appWith(MemorySettingsStore('test-key'), client: client),
    );
    await tester.pumpAndSettle();
    final initial = weatherRequests;
    // Every saved city is fetched up front.
    expect(initial, cityCatalog.length);

    await tester.fling(find.text('北京'), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(weatherRequests, greaterThan(initial));
  });

  testWidgets('returning from the background reloads the weather', (
    WidgetTester tester,
  ) async {
    var weatherRequests = 0;
    final client = MockClient((request) async {
      weatherRequests++;
      return http.Response(sampleWeatherResponse, 200);
    });

    await tester.pumpWidget(app(apiKey: 'test-key', client: client));
    await tester.pumpAndSettle();
    final initial = weatherRequests;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    // Nothing is fetched while the app sits in the background.
    expect(weatherRequests, initial);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    // Every saved city is reloaded, and the last weather stays on screen.
    expect(weatherRequests, initial + cityCatalog.length);
    expect(find.text('北京'), findsOneWidget);
  });

  testWidgets('a transient interruption does not reload the weather', (
    WidgetTester tester,
  ) async {
    var weatherRequests = 0;
    final client = MockClient((request) async {
      weatherRequests++;
      return http.Response(sampleWeatherResponse, 200);
    });

    await tester.pumpWidget(app(apiKey: 'test-key', client: client));
    await tester.pumpAndSettle();
    final initial = weatherRequests;

    // The notification shade or a system dialog only makes the app inactive.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(weatherRequests, initial);
  });
}
