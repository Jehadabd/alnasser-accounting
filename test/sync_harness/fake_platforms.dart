// test/sync_harness/fake_platforms.dart
// منصات وهمية لكل جهاز: Firebase الأساسية، المصادقة، فحص الإنترنت، مسارات الملفات.
// تُركَّب على مستوى «المنصة» فتعمل مكتبات Firebase ومكتبات Flutter كما هي.

// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakeFirebaseCore extends FirebasePlatform {
  final Map<String, FirebaseAppPlatform> _apps = {};

  FakeFirebaseCore() {
    _apps[defaultFirebaseAppName] = FirebaseAppPlatform(
      defaultFirebaseAppName,
      const FirebaseOptions(
        apiKey: 'harness',
        appId: '1:1:harness:1',
        messagingSenderId: '1',
        projectId: 'sync-harness',
      ),
    );
  }

  @override
  List<FirebaseAppPlatform> get apps => _apps.values.toList();

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) {
    final a = _apps[name];
    if (a == null) throw noAppExists(name);
    return a;
  }

  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async =>
      app(name ?? defaultFirebaseAppName);
}

class _FakeMultiFactor extends MultiFactorPlatform {
  _FakeMultiFactor(super.auth);
}

class _FakeCredential extends UserCredentialPlatform {
  _FakeCredential(FirebaseAuthPlatform auth, UserPlatform? user) : super(auth: auth, user: user);
}

class FakeUser extends UserPlatform {
  final String uidValue;
  FakeUser(FirebaseAuthPlatform auth, this.uidValue)
      : super(
          auth,
          _FakeMultiFactor(auth),
          PigeonUserDetails(
            userInfo: PigeonUserInfo(uid: uidValue, isAnonymous: true, isEmailVerified: false),
            providerData: const [],
          ),
        );

  @override
  Future<String?> getIdToken(bool forceRefresh) async => 'token-$uidValue';
}

class FakeAuth extends FirebaseAuthPlatform {
  final String uid;
  UserPlatform? _user;
  final StreamController<UserPlatform?> _changes = StreamController.broadcast();

  FakeAuth(this.uid) : super() {
    _user = FakeUser(this, uid);
  }

  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAuthPlatform setInitialValues({PigeonUserDetails? currentUser, String? languageCode}) =>
      this;

  @override
  UserPlatform? get currentUser => _user;

  @override
  set currentUser(UserPlatform? userPlatform) => _user = userPlatform;

  Stream<UserPlatform?> _stream() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  Stream<UserPlatform?> authStateChanges() => _stream();
  @override
  Stream<UserPlatform?> idTokenChanges() => _stream();
  @override
  Stream<UserPlatform?> userChanges() => _stream();

  @override
  Future<UserCredentialPlatform> signInAnonymously() async {
    _user = FakeUser(this, uid);
    _changes.add(_user);
    return _FakeCredential(this, _user);
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _changes.add(null);
  }

  @override
  Future<void> setPersistence(Persistence persistence) async {}
}

class FakeConnectivity extends ConnectivityPlatform {
  bool online;
  final StreamController<List<ConnectivityResult>> _ctl = StreamController.broadcast();
  FakeConnectivity(this.online);

  void setOnline(bool value) {
    online = value;
    _ctl.add([value ? ConnectivityResult.wifi : ConnectivityResult.none]);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [online ? ConnectivityResult.wifi : ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _ctl.stream;
}

class FakePathProvider extends PathProviderPlatform {
  final String dir;
  FakePathProvider(this.dir);
  @override
  Future<String?> getTemporaryPath() async => '$dir/tmp';
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getLibraryPath() async => dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationCachePath() async => '$dir/cache';
  @override
  Future<String?> getDownloadsPath() async => '$dir/downloads';
}
