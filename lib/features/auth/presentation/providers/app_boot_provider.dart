import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/secure_storage_service.dart';
import '../../data/models/user.dart';
import 'auth_providers.dart';

/// One-shot provider that boots the auth state from secure storage
/// BEFORE the first frame is painted.
///
/// `main.dart` watches this provider and shows
/// `FullScreenLoadingSkeleton` until it resolves. By that time, if a
/// session existed, the auth notifier has already been hydrated to
/// [AuthAuthenticated], and the router redirects straight to the
/// role's dashboard — no flash of the login screen.
///
/// Side effect: fires GET /auth/me in the background to refresh the
/// cached user data. Failures are silent (network may be unavailable
/// at boot — that's fine, we'll re-fetch later).
final appBootProvider = FutureProvider<void>((ref) async {
  final storage = ref.read(secureStorageProvider);
  final hasSession = await storage.hasSession();
  if (!hasSession) return;

  final cachedJson = await storage.readUserJson();
  if (cachedJson == null) return;

  final User user;
  try {
    user = User.fromJson(cachedJson);
  } catch (_) {
    // Corrupt cache — wipe and start clean.
    await storage.clearAll();
    return;
  }

  // Hydrate state synchronously so the router's redirect runs with
  // AuthAuthenticated on the very first build.
  ref.read(authStateProvider.notifier).hydrate(user);

  // Fire-and-forget refresh of the user record. We deliberately do
  // NOT await — boot must not block on the network. If /auth/me fails,
  // the cached user remains in place and we'll re-try on next launch.
  // ignore: unawaited_futures
  ref.read(authRepositoryProvider).refreshCurrentUser().then((fresh) {
    // Guard against a logout that happened while /auth/me was in flight
    // (Render cold-start makes this a 30–60s window). Without this check,
    // a late success would call hydrate() and snap the just-logged-out
    // user back into the app, then bounce them out again once the cleared
    // token starts forcing 401s.
    if (fresh != null &&
        ref.read(authStateProvider) is AuthAuthenticated) {
      ref.read(authStateProvider.notifier).hydrate(fresh);
    }
  });
});
