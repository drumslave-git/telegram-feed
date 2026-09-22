import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'drive_sync_store.dart';

/// Web OAuth client id of the Google Cloud project that owns the app's Android OAuth client
/// (package name + signing SHA-1). Not a secret, but project-specific, so it comes from
/// `--dart-define=GOOGLE_SERVER_CLIENT_ID=...` like the Telegram credentials.
const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

/// Google account access for Drive sync. Abstract so the controller and screens are tested
/// without Play services.
abstract interface class DriveAuth {
  /// False when the build has no Google client id; sync is then unavailable.
  bool get isConfigured;

  /// Restores the previous sign-in. Returns the account's email, or null when the user has
  /// to sign in again. With [knownEmail], the account this device signed in with before,
  /// it only asks for the Drive token, which shows no UI; without it Google may show its
  /// "Signing you in" sheet for a moment.
  Future<String?> restore({String? knownEmail});

  /// Interactive sign-in and consent for the Drive app data scope. Returns the email.
  Future<String> signIn();

  /// Access token for [DriveSyncStore.scope], or null when not signed in or not consented.
  Future<String?> accessToken({bool fresh = false});

  Future<void> signOut();
}

/// `google_sign_in` 7: authentication (who) and authorization (Drive scope) are separate.
final class GoogleDriveAuth implements DriveAuth {
  GoogleSignInAccount? _account;

  /// Signed in by [restore] through the Drive token alone, without an account object.
  bool _tokenOnly = false;
  Future<void>? _init;

  @override
  bool get isConfigured => googleServerClientId.isNotEmpty;

  Future<void> _ensureInit() => _init ??= GoogleSignIn.instance.initialize(
    serverClientId: googleServerClientId,
  );

  @override
  Future<String?> restore({String? knownEmail}) async {
    if (!isConfigured) return null;
    try {
      await _ensureInit();
      if (knownEmail != null) {
        final auth = await GoogleSignIn.instance.authorizationClient
            .authorizationForScopes(const [DriveSyncStore.scope]);
        _tokenOnly = auth != null;
        return _tokenOnly ? knownEmail : null;
      }
      _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    } on GoogleSignInException catch (e) {
      debugPrint('sync: silent sign-in failed: ${e.code}');
      _account = null;
      _tokenOnly = false;
    }
    return _account?.email;
  }

  @override
  Future<String> signIn() async {
    if (!isConfigured) {
      throw const SyncException('This build has no Google client id.');
    }
    try {
      await _ensureInit();
      final account = _account = await GoogleSignIn.instance.authenticate(
        scopeHint: const [DriveSyncStore.scope],
      );
      await account.authorizationClient.authorizeScopes(const [
        DriveSyncStore.scope,
      ]);
      return account.email;
    } on GoogleSignInException catch (e) {
      throw SyncException(
        e.code == GoogleSignInExceptionCode.canceled
            ? 'Sign-in was cancelled.'
            : 'Google sign-in failed: ${e.description ?? e.code.name}',
      );
    }
  }

  @override
  Future<String?> accessToken({bool fresh = false}) async {
    final account = _account;
    if (account == null && !_tokenOnly) return null;
    try {
      final client =
          account?.authorizationClient ??
          GoogleSignIn.instance.authorizationClient;
      if (fresh) {
        final old = await client.authorizationForScopes(const [
          DriveSyncStore.scope,
        ]);
        if (old != null) {
          await client.clearAuthorizationToken(accessToken: old.accessToken);
        }
      }
      final auth = await client.authorizationForScopes(const [
        DriveSyncStore.scope,
      ]);
      return auth?.accessToken;
    } on GoogleSignInException catch (e) {
      debugPrint('sync: no access token: ${e.code}');
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    _account = null;
    _tokenOnly = false;
    if (!isConfigured) return;
    try {
      await _ensureInit();
      await GoogleSignIn.instance.signOut();
    } on GoogleSignInException catch (e) {
      debugPrint('sync: sign-out failed: ${e.code}');
    }
  }
}
