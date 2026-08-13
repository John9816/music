# DuckMusic Auth Session Continuity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve valid Android 1.1.26 sessions across the Flutter upgrade and make login, refresh, expiry, and logout state transitions reliable.

**Architecture:** A focused Dart platform-source abstraction reads and clears a structured legacy session over a MethodChannel. `AuthController` remains the single session-state owner, persists the migrated credentials before acknowledging migration, and applies one expiry/refresh policy to load, login, registration, and token rotation. Android isolates old `EncryptedSharedPreferences` compatibility in a testable reader; the backend protocol remains unchanged.

**Tech Stack:** Flutter/Dart, `shared_preferences`, Flutter MethodChannel, Kotlin, AndroidX Security Crypto, JUnit 4, Flutter test, Spring Boot auth integration tests.

---

## File Map

- Create `lib/core/auth/legacy_auth_session.dart`: typed legacy session and MethodChannel-backed source.
- Modify `lib/core/auth/auth_controller.dart`: migration orchestration, expiry persistence, response aliases, truthful login state, and legacy cleanup.
- Modify `lib/core/api/auth_api.dart`: injectable client plus refresh/logout compatibility payloads.
- Create `android/app/src/main/kotlin/com/music/player/LegacyAuthSessionStore.kt`: old secure/plain/mirror preference access and validation.
- Modify `android/app/src/main/kotlin/com/music/player/MainActivity.kt`: register the migration channel only.
- Modify `android/app/build.gradle.kts`: add AndroidX Security Crypto and JUnit dependencies.
- Create `test/legacy_auth_session_test.dart`: Dart bridge parsing and channel contract tests.
- Create `test/auth_api_test.dart`: refresh/logout wire-format tests.
- Modify `test/auth_session_test.dart`: migration, aliases, expiry, login-state, logout, and cleanup regressions.
- Create `android/app/src/test/kotlin/com/music/player/LegacyAuthSessionStoreTest.kt`: store priority, validation, fallback, and idempotent clear tests.

## Task 1: Dart Legacy Session Contract

**Files:**
- Create: `lib/core/auth/legacy_auth_session.dart`
- Create: `test/legacy_auth_session_test.dart`

- [ ] **Step 1: Write failing parsing and channel tests**

Add tests that parse numeric and string expiry values, reject partial token pairs, verify the `readLegacyAuthSession` method result, and verify `clearLegacyAuthSession` is sent only through the explicit clear call:

```dart
test('parses a complete legacy session', () {
  final session = LegacyAuthSession.fromMap(const {
    'accessToken': 'legacy-access',
    'refreshToken': 'legacy-refresh',
    'expiresAtMs': 123456,
    'userId': '42',
  });

  expect(session?.accessToken, 'legacy-access');
  expect(session?.refreshToken, 'legacy-refresh');
  expect(session?.expiresAtMs, 123456);
  expect(session?.userId, '42');
});

test('rejects a partial legacy session', () {
  expect(
    LegacyAuthSession.fromMap(const {'accessToken': 'legacy-access'}),
    isNull,
  );
});
```

- [ ] **Step 2: Run the Dart bridge test and confirm failure**

Run: `flutter test test/legacy_auth_session_test.dart`

Expected: FAIL because `legacy_auth_session.dart` and its types do not exist.

- [ ] **Step 3: Implement the typed source and MethodChannel adapter**

Implement this complete adapter:

```dart
import 'package:flutter/services.dart';

class LegacyAuthSession {
  const LegacyAuthSession({
    required this.accessToken,
    required this.refreshToken,
    this.expiresAtMs,
    this.userId,
  });

  final String accessToken;
  final String refreshToken;
  final int? expiresAtMs;
  final String? userId;

  static LegacyAuthSession? fromMap(Map<Object?, Object?> values) {
    final accessToken = _string(values['accessToken']);
    final refreshToken = _string(values['refreshToken']);
    if (accessToken == null || refreshToken == null) return null;
    return LegacyAuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAtMs: _positiveInt(values['expiresAtMs']),
      userId: _string(values['userId']),
    );
  }

  static String? _string(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static int? _positiveInt(Object? value) {
    final parsed = value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }
}

abstract interface class LegacyAuthSessionSource {
  Future<LegacyAuthSession?> read();
  Future<void> clear();
}

class MethodChannelLegacyAuthSessionSource implements LegacyAuthSessionSource {
  const MethodChannelLegacyAuthSessionSource();
  static const MethodChannel channel = MethodChannel('duckmusic/legacy_auth_session');

  @override
  Future<LegacyAuthSession?> read() async {
    try {
      final values = await channel.invokeMethod<Object?>('readLegacyAuthSession');
      return values is Map
          ? LegacyAuthSession.fromMap(Map<Object?, Object?>.from(values))
          : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    try {
      await channel.invokeMethod<void>('clearLegacyAuthSession');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
```

The adapter must not print token values. `MissingPluginException` and `PlatformException` are non-fatal because non-Android hosts have no legacy store.

- [ ] **Step 4: Run the bridge tests and confirm pass**

Run: `flutter test test/legacy_auth_session_test.dart`

Expected: PASS.

## Task 2: Refresh and Logout Wire Protocol

**Files:**
- Modify: `lib/core/api/auth_api.dart`
- Create: `test/auth_api_test.dart`

- [ ] **Step 1: Write failing HTTP payload tests**

Use `ApiClient.forTesting(MockClient(...))` and construct `AuthApi(client: client)`. Decode each request body and assert:

```dart
expect(refreshBody, {
  'refresh_token': 'rotating-refresh',
  'refreshToken': 'rotating-refresh',
});

expect(logoutBody, {
  'refresh_token': 'logout-refresh',
  'refreshToken': 'logout-refresh',
});
expect(request.headers['authorization'], 'Bearer logout-access');
```

Return `{ "code": 0, "data": {} }` from the mock server.

- [ ] **Step 2: Run the API tests and confirm failure**

Run: `flutter test test/auth_api_test.dart`

Expected: FAIL because `AuthApi` cannot receive a test client and logout has no refresh-token body.

- [ ] **Step 3: Implement the compatibility payloads**

Change `AuthApi` to:

```dart
class AuthApi {
  AuthApi({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<Map<String, dynamic>> refreshToken(String refresh) {
    return _client.postJson(
      'api/auth/refresh',
      body: {'refresh_token': refresh, 'refreshToken': refresh},
      retryUnauthorized: false,
    );
  }

  Future<void> logout(
    String refreshToken, {
    String? accessToken,
  }) async {
    await _client.postJson(
      'api/auth/logout',
      body: {
        'refresh_token': refreshToken,
        'refreshToken': refreshToken,
      },
      headers: {
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      retryUnauthorized: false,
    );
  }
}
```

- [ ] **Step 4: Run API tests and confirm pass**

Run: `flutter test test/auth_api_test.dart`

Expected: PASS.

## Task 3: Flutter Migration Orchestration

**Files:**
- Modify: `lib/core/auth/auth_controller.dart`
- Modify: `test/auth_session_test.dart`

- [ ] **Step 1: Write failing migration tests**

Add `_FakeLegacyAuthSessionSource` with `readCalls` and `clearCalls`:

```dart
test('migrates and acknowledges a complete Android legacy session', () async {
  SharedPreferences.setMockInitialValues(const {});
  final source = _FakeLegacyAuthSessionSource(
    session: const LegacyAuthSession(
      accessToken: 'legacy-access',
      refreshToken: 'legacy-refresh',
      expiresAtMs: 4102444800000,
      userId: '42',
    ),
  );
  final auth = AuthController(api: _FakeAuthApi(), legacySessionSource: source);

  await auth.load();

  final prefs = await SharedPreferences.getInstance();
  expect(auth.token, 'legacy-access');
  expect(prefs.getString('auth_refresh_token'), 'legacy-refresh');
  expect(prefs.getInt('auth_expires_at_ms'), 4102444800000);
  expect(source.clearCalls, 1);
});

class _FakeLegacyAuthSessionSource implements LegacyAuthSessionSource {
  _FakeLegacyAuthSessionSource({this.session, this.readError});

  final LegacyAuthSession? session;
  final Object? readError;
  int readCalls = 0;
  int clearCalls = 0;

  @override
  Future<LegacyAuthSession?> read() async {
    readCalls++;
    if (readError != null) throw readError!;
    return session;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
  }
}
```

Also assert a current Flutter token prevents any legacy read, and a source read failure leaves the app initialized and logged out.

- [ ] **Step 2: Run the session tests and confirm failure**

Run: `flutter test test/auth_session_test.dart`

Expected: FAIL because `AuthController` has no migration-source dependency or expiry/user ID keys.

- [ ] **Step 3: Implement migration-before-restore**

Inject `LegacyAuthSessionSource` with a MethodChannel default. Add `_expiresAtMs` and `_userId`, load them from `auth_expires_at_ms` and `auth_user_id`, and attempt migration only when both Flutter token fields are absent.

Persist the four legacy values, require every setter to return success, and read the values back before calling `source.clear()`. On failed verification, remove only the partially written Flutter auth keys, reset in-memory migrated values, and retain the old Android stores for a future retry.

- [ ] **Step 4: Run the session tests and confirm pass**

Run: `flutter test test/auth_session_test.dart`

Expected: PASS, including all pre-existing offline and refresh-retention cases.

## Task 4: Expiry, Alias, and Truthful State Rules

**Files:**
- Modify: `lib/core/auth/auth_controller.dart`
- Modify: `test/auth_session_test.dart`

- [ ] **Step 1: Write failing lifecycle tests**

Extend `_FakeAuthApi` with an `onLogin` callback and captured logout arguments, then add these concrete cases:

```dart
test('refresh response accepts the refresh alias', () async {
  SharedPreferences.setMockInitialValues(const {
    'auth_token': 'expired-access',
    'auth_refresh_token': 'old-refresh',
  });
  var profileCalls = 0;
  final api = _FakeAuthApi(
    onGetMe: (_) async {
      profileCalls++;
      if (profileCalls == 1) {
        throw ApiException('expired', unauthorized: true, statusCode: 401);
      }
      return {'username': '用户'};
    },
    onRefresh: (_) async => {
      'token': 'new-access',
      'refresh': 'new-refresh',
      'expiresInMinutes': 120,
    },
  );

  await AuthController(api: api, now: () => DateTime.fromMillisecondsSinceEpoch(1000)).load();

  final prefs = await SharedPreferences.getInstance();
  expect(prefs.getString('auth_token'), 'new-access');
  expect(prefs.getString('auth_refresh_token'), 'new-refresh');
  expect(prefs.getInt('auth_expires_at_ms'), 7201000);
});

test('near-expiry token refreshes before profile restoration', () async {
  SharedPreferences.setMockInitialValues(const {
    'auth_token': 'near-expiry-access',
    'auth_refresh_token': 'valid-refresh',
    'auth_expires_at_ms': 30000,
  });
  final calls = <String>[];
  final api = _FakeAuthApi(
    onRefresh: (_) async {
      calls.add('refresh');
      return {
        'token': 'new-access',
        'refreshToken': 'new-refresh',
        'expiresInMinutes': 120,
      };
    },
    onGetMe: (token) async {
      calls.add('getMe:$token');
      return {'username': '用户'};
    },
  );

  await AuthController(
    api: api,
    now: () => DateTime.fromMillisecondsSinceEpoch(0),
  ).load();

  expect(calls, ['refresh', 'getMe:new-access']);
});

test('login returns false when profile restoration invalidates the session', () async {
  SharedPreferences.setMockInitialValues(const {});
  final api = _FakeAuthApi(
    onLogin: (_, __) async => {
      'token': 'rejected-access',
      'refreshToken': 'rejected-refresh',
    },
    onGetMe: (_) async => throw ApiException(
      'expired',
      unauthorized: true,
      statusCode: 401,
    ),
    onRefresh: (_) async => throw ApiException(
      'invalid refresh',
      unauthorized: true,
      statusCode: 401,
    ),
  );
  final auth = AuthController(api: api);

  expect(await auth.login('user', 'password'), isFalse);
  expect(auth.isLoggedIn, isFalse);
});

test('logout submits refresh token and clears legacy storage', () async {
  SharedPreferences.setMockInitialValues(const {
    'auth_token': 'logout-access',
    'auth_refresh_token': 'logout-refresh',
  });
  final api = _FakeAuthApi();
  final source = _FakeLegacyAuthSessionSource();
  final auth = AuthController(api: api, legacySessionSource: source);
  await auth.load();

  await auth.logout();

  expect(api.logoutRefreshToken, 'logout-refresh');
  expect(api.logoutAccessToken, 'logout-access');
  expect(source.clearCalls, 1);
});
```

Cover `refresh_token_value` as a second alias assertion and `expires_in` seconds as an expiry input.

- [ ] **Step 2: Run lifecycle tests and confirm failure**

Run: `flutter test test/auth_session_test.dart`

Expected: FAIL on aliases, proactive refresh, login return value, or logout arguments.

- [ ] **Step 3: Implement one response/session policy**

Add helpers with these signatures:

```dart
String? _pickAny(Map<String, dynamic> data, Iterable<String> keys);
int? _readPositiveInt(Map<String, dynamic> data, Iterable<String> keys);
int? _resolveExpiresAtMs(Map<String, dynamic> data, String accessToken);
int? _jwtExpiresAtMs(String accessToken);
bool get _accessTokenNearExpiry;
```

Recognize refresh aliases `refreshToken`, `refresh_token`, `refresh`, and `refresh_token_value`. Resolve expiry in this order: absolute milliseconds, seconds duration, minutes duration, JWT `exp`, unknown. Use a 60-second safety window and preserve unknown expiry as `null` rather than forcing refresh.

Before `_restoreProfile()` during `load()`, refresh a near-expiry token when a refresh token exists. After login/register profile restoration, return success only when `_token` still exists. In `logout()`, snapshot both tokens, call the API with the refresh token, and use `finally` to clear Flutter and legacy storage.

- [ ] **Step 4: Run lifecycle tests and confirm pass**

Run: `flutter test test/auth_session_test.dart test/auth_api_test.dart test/legacy_auth_session_test.dart`

Expected: PASS.

## Task 5: Android Old-Preference Reader

**Files:**
- Create: `android/app/src/main/kotlin/com/music/player/LegacyAuthSessionStore.kt`
- Create: `android/app/src/test/kotlin/com/music/player/LegacyAuthSessionStoreTest.kt`
- Modify: `android/app/src/main/kotlin/com/music/player/MainActivity.kt`
- Modify: `android/app/build.gradle.kts`

- [ ] **Step 1: Add Android test and compatibility dependencies**

Add:

```kotlin
dependencies {
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    testImplementation("junit:junit:4.13.2")
}
```

- [ ] **Step 2: Write failing pure Kotlin store tests**

Use in-memory `LegacyPreferenceStore` fakes to assert secure-first priority, provider-exception fallback to plain, incomplete-session fallback to mirror, numeric/string expiry parsing, read-without-clear, and clearing every available provider. The main assertion shape is:

```kotlin
assertEquals("secure-access", reader.read()?.accessToken)
assertEquals(0, secure.clearCalls)
reader.clear()
assertEquals(1, secure.clearCalls)
assertEquals(1, plain.clearCalls)
assertEquals(1, mirror.clearCalls)
```

- [ ] **Step 3: Run the Android test and confirm failure**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests com.music.player.LegacyAuthSessionStoreTest`

Expected: FAIL because the reader types do not exist.

- [ ] **Step 4: Implement the store and Android adapters**

Define these complete pure/store-facing types; Android adapters are supplied by `fromContext`:

```kotlin
package com.music.player

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

private const val SECURE_PREFS = "auth_prefs_secure"
private const val PLAIN_PREFS = "auth_prefs"
private const val MIRROR_PREFS = "auth_prefs_mirror"

private object LegacyAuthKeys {
    const val ACCESS_TOKEN = "access_token"
    const val REFRESH_TOKEN = "refresh_token"
    const val EXPIRES_AT_MS = "expires_at_ms"
    const val USER_ID = "user_id"
    val all = listOf(ACCESS_TOKEN, REFRESH_TOKEN, EXPIRES_AT_MS, USER_ID)
}

internal data class LegacyAuthSession(
    val accessToken: String,
    val refreshToken: String,
    val expiresAtMs: Long?,
    val userId: String?,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "accessToken" to accessToken,
        "refreshToken" to refreshToken,
        "expiresAtMs" to expiresAtMs,
        "userId" to userId,
    )
}

internal interface LegacyPreferenceStore {
    fun value(key: String): Any?
    fun clearSession()
}

private class SharedPreferencesLegacyStore(
    private val preferences: SharedPreferences,
) : LegacyPreferenceStore {
    override fun value(key: String): Any? = preferences.all[key]

    override fun clearSession() {
        val editor = preferences.edit()
        LegacyAuthKeys.all.forEach(editor::remove)
        editor.commit()
    }
}

internal class LegacyAuthSessionStore(
    private val providers: List<() -> LegacyPreferenceStore?>,
) {
    fun read(): LegacyAuthSession? {
        for (provider in providers) {
            val store = runCatching { provider() }.getOrNull() ?: continue
            val accessToken = store.value(LegacyAuthKeys.ACCESS_TOKEN)
                ?.toString()?.trim().orEmpty()
            val refreshToken = store.value(LegacyAuthKeys.REFRESH_TOKEN)
                ?.toString()?.trim().orEmpty()
            if (accessToken.isEmpty() || refreshToken.isEmpty()) continue
            return LegacyAuthSession(
                accessToken = accessToken,
                refreshToken = refreshToken,
                expiresAtMs = positiveLong(store.value(LegacyAuthKeys.EXPIRES_AT_MS)),
                userId = store.value(LegacyAuthKeys.USER_ID)
                    ?.toString()?.trim()?.takeIf(String::isNotEmpty),
            )
        }
        return null
    }

    fun clear() {
        providers.forEach { provider ->
            runCatching { provider()?.clearSession() }
        }
    }

    private fun positiveLong(value: Any?): Long? {
        val parsed = when (value) {
            is Number -> value.toLong()
            else -> value?.toString()?.toLongOrNull()
        }
        return parsed?.takeIf { it > 0L }
    }

    companion object {
        fun fromContext(context: Context): LegacyAuthSessionStore {
            val applicationContext = context.applicationContext
            return LegacyAuthSessionStore(
                listOf(
                    {
                        val masterKey = MasterKey.Builder(applicationContext)
                            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                            .build()
                        val preferences = EncryptedSharedPreferences.create(
                            applicationContext,
                            SECURE_PREFS,
                            masterKey,
                            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
                        )
                        SharedPreferencesLegacyStore(preferences)
                    },
                    {
                        SharedPreferencesLegacyStore(
                            applicationContext.getSharedPreferences(
                                PLAIN_PREFS,
                                Context.MODE_PRIVATE,
                            ),
                        )
                    },
                    {
                        SharedPreferencesLegacyStore(
                            applicationContext.getSharedPreferences(
                                MIRROR_PREFS,
                                Context.MODE_PRIVATE,
                            ),
                        )
                    },
                ),
            )
        }
    }
}
```

The secure provider must use `MasterKey.KeyScheme.AES256_GCM`, key scheme `AES256_SIV`, value scheme `AES256_GCM`, file `auth_prefs_secure`, and the same application ID/context as 1.1.26. Plain and mirror files are `auth_prefs` and `auth_prefs_mirror`. Clear only `access_token`, `refresh_token`, `expires_at_ms`, and `user_id`, using synchronous `commit()`.

- [ ] **Step 5: Register the migration channel**

In `MainActivity.configureFlutterEngine`, create one `LegacyAuthSessionStore` and register channel `duckmusic/legacy_auth_session`:

```kotlin
when (call.method) {
    "readLegacyAuthSession" -> result.success(legacyAuthStore.read()?.toMap())
    "clearLegacyAuthSession" -> {
        legacyAuthStore.clear()
        result.success(null)
    }
    else -> result.notImplemented()
}
```

- [ ] **Step 6: Run Android tests and compile the debug host**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests com.music.player.LegacyAuthSessionStoreTest`

Expected: PASS.

Run: `flutter build apk --debug`

Expected: build succeeds and packages AndroidX Security Crypto.

## Task 6: Final Regression Verification

**Files:**
- Verify only; no unrelated production edits.

- [ ] **Step 1: Format changed Dart and Kotlin files**

Run: `dart format lib/core/auth/legacy_auth_session.dart lib/core/auth/auth_controller.dart lib/core/api/auth_api.dart test/legacy_auth_session_test.dart test/auth_api_test.dart test/auth_session_test.dart`

Run: `cd android && ./gradlew :app:ktlintCheck`

Expected: Dart formatter succeeds. If this repository has no `ktlintCheck` task, record that fact and rely on Kotlin compilation without adding a formatter plugin.

- [ ] **Step 2: Run focused Flutter tests**

Run: `flutter test test/legacy_auth_session_test.dart test/auth_api_test.dart test/auth_session_test.dart test/api_client_test.dart`

Expected: PASS.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze`

Expected: no new errors or warnings from changed files.

- [ ] **Step 4: Run Android unit tests and debug build**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests com.music.player.LegacyAuthSessionStoreTest`

Run: `flutter build apk --debug`

Expected: both succeed.

- [ ] **Step 5: Re-run backend auth integration tests without modifying backend code**

Run from `/Users/wangweijie/projects/idea/website-backend`: `mvn -Dtest=AuthRefreshIntegrationTests test`

Expected: PASS, confirming refresh rotation and logout revocation still match the client payload.

- [ ] **Step 6: Review the final diff**

Run: `git diff --check`

Run: `git diff -- lib/core/auth lib/core/api/auth_api.dart android/app/src/main/kotlin/com/music/player android/app/src/test/kotlin/com/music/player android/app/build.gradle.kts test/auth_session_test.dart test/auth_api_test.dart test/legacy_auth_session_test.dart docs/superpowers`

Expected: only authentication continuity changes and approved documentation appear; existing unrelated user changes remain untouched.

No commit step is included because the current task did not request creating commits.
