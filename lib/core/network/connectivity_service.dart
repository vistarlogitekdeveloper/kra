import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when the device has at least one non-`none` connectivity type.
///
/// Note: this only checks whether a network interface is up. It does NOT
/// guarantee that the backend is reachable — the offline banner is a
/// hint, not a contract.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();

  // Emit the current state immediately so subscribers don't see `loading`
  // for ~1s on cold start.
  final initial = await connectivity.checkConnectivity();
  yield _isOnline(initial);

  await for (final result in connectivity.onConnectivityChanged) {
    yield _isOnline(result);
  }
});

bool _isOnline(dynamic result) {
  // `connectivity_plus` 5.x: returns either ConnectivityResult or
  // List<ConnectivityResult> across versions/platforms — handle both
  // shapes defensively.
  if (result is ConnectivityResult) {
    return result != ConnectivityResult.none;
  }
  if (result is List<ConnectivityResult>) {
    if (result.isEmpty) return false;
    return result.any((r) => r != ConnectivityResult.none);
  }
  return true;
}
