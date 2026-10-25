import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lumina_tdlib/api.dart' as td;

import '../../../core/config/app_config.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/tdlib/td_client.dart';
import '../../../core/tdlib/td_paths.dart';

/// The auth feature's only door to TDLib, secure storage and the file system.
///
/// Methods complete when TDLib accepts the request and throw
/// `TdException` / `TdTransportException` otherwise; the resulting state
/// change always arrives through [authorizationStates].
class AuthRepository {
  AuthRepository({
    required this._client,
    required this._secureStore,
    required this._paths,
    required this._settings,
  });

  final TdClient _client;
  final SecureStore _secureStore;
  final TdPaths _paths;
  final TdSettings _settings;

  bool get hasApiCredentials => _settings.hasApiCredentials;

  Stream<td.AuthorizationState> get authorizationStates => _client.updates
      .where((u) => u is td.UpdateAuthorizationState)
      .map((u) => (u as td.UpdateAuthorizationState).authorizationState);

  Future<void> start() async {
    await _client.start();
    await _client.execute(td.SetLogVerbosityLevel(newVerbosityLevel: kReleaseMode ? 1 : 2));
  }

  Future<void> sendTdlibParameters() async {
    final key = await _secureStore.databaseEncryptionKey();
    await _client.invoke<td.Ok>(
      td.SetTdlibParameters(
        useTestDc: _settings.useTestDc,
        databaseDirectory: _paths.database,
        filesDirectory: _paths.files,
        databaseEncryptionKey: key,
        useFileDatabase: true,
        useChatInfoDatabase: true,
        useMessageDatabase: true,
        useSecretChats: true,
        apiId: _settings.apiId,
        apiHash: _settings.apiHash,
        systemLanguageCode: Platform.localeName.split(RegExp('[_.]')).first,
        deviceModel: 'Android',
        systemVersion: Platform.operatingSystemVersion,
        applicationVersion: _settings.applicationVersion,
      ),
    );
  }

  /// Spaces, dashes and parentheses are stripped; TDLib wants `+` and digits.
  Future<void> setPhoneNumber(String phoneNumber) => _client.invoke<td.Ok>(
    td.SetAuthenticationPhoneNumber(phoneNumber: phoneNumber.replaceAll(RegExp(r'[\s()-]'), '')),
  );

  /// Valid only in `authorizationStateWaitPhoneNumber`.
  Future<void> checkBotToken(String token) =>
      _client.invoke<td.Ok>(td.CheckAuthenticationBotToken(token: token.trim()));

  Future<void> checkCode(String code) => _client.invoke<td.Ok>(td.CheckAuthenticationCode(code: code.trim()));

  Future<void> resendCode() => _client.invoke<td.Ok>(const td.ResendAuthenticationCode());

  Future<void> checkPassword(String password) =>
      _client.invoke<td.Ok>(td.CheckAuthenticationPassword(password: password));

  Future<void> register(String firstName, String lastName) => _client.invoke<td.Ok>(
    td.RegisterUser(firstName: firstName.trim(), lastName: lastName.trim(), disableNotification: false),
  );

  Future<void> setEmailAddress(String email) =>
      _client.invoke<td.Ok>(td.SetAuthenticationEmailAddress(emailAddress: email.trim()));

  Future<void> checkEmailCode(String code) => _client.invoke<td.Ok>(
    td.CheckAuthenticationEmailCode(code: td.EmailAddressAuthenticationCode(code: code.trim())),
  );

  Future<td.User> getMe() => _client.invoke<td.User>(const td.GetMe());

  /// Terminates the server session. If the server cannot be reached the
  /// client is still closed, so the local wipe at `Closed` leaves nothing
  /// that could auto-authenticate.
  Future<void> logOut() async {
    try {
      await _client.invoke<td.Ok>(const td.LogOut());
    } on Exception {
      await _client.invoke<td.Ok>(const td.Close()).catchError((_) => const td.Ok());
    }
  }

  /// Closes TDLib and destroys its local data without a server logout.
  Future<void> destroy() => _client.invoke<td.Ok>(const td.Destroy()).catchError((_) => const td.Ok());

  /// Deletes the database, files and encryption key. Only after `Closed`.
  Future<void> wipeLocalData() async {
    await _paths.wipe();
    await _secureStore.discardDatabaseEncryptionKey();
  }

  /// TDLib cannot reuse a closed client; the new one restarts the flow at
  /// `authorizationStateWaitTdlibParameters`.
  Future<void> recreateClient() => _client.recreateAfterClose();
}
