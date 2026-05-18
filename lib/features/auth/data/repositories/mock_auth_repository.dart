import '../models/user.dart';
import 'auth_repository.dart';

/// In-memory [AuthRepository] used for offline UI development and tests.
///
/// To switch the app to the mock, edit `auth_providers.dart` and have
/// `authRepositoryProvider` return `MockAuthRepository()` instead of
/// `ApiAuthRepository(...)`. Nothing else in the app needs to change.
///
/// Test passwords are all `password123` — these are not real credentials.
class MockAuthRepository implements AuthRepository {
  User? _currentUser;

  static const _orgId = 'mock-org-001';

  static const Map<String, _MockAccount> _accounts = {
    'admin@vistar.com': _MockAccount(
      password: 'password123',
      user: User(
        id: '0',
        email: 'admin@vistar.com',
        fullName: 'System Admin',
        role: UserRole.admin,
        organizationId: _orgId,
      ),
    ),
    'pravin@vistar.com': _MockAccount(
      password: 'password123',
      user: User(
        id: '1',
        email: 'pravin@vistar.com',
        fullName: 'Pravin Suryakant Wakchware',
        role: UserRole.employee,
        organizationId: _orgId,
        projectLocationId: 'site-chakan-b22',
      ),
    ),
    'amol@vistar.com': _MockAccount(
      password: 'password123',
      user: User(
        id: '2',
        email: 'amol@vistar.com',
        fullName: 'Amol Laxman Veer',
        role: UserRole.manager,
        organizationId: _orgId,
        projectLocationId: 'site-pune-ho',
      ),
    ),
    'murali@vistar.com': _MockAccount(
      password: 'password123',
      user: User(
        id: '3',
        email: 'murali@vistar.com',
        fullName: 'Muralidharan Krishnan',
        role: UserRole.ops,
        organizationId: _orgId,
      ),
    ),
    'swati@vistar.com': _MockAccount(
      password: 'password123',
      user: User(
        id: '4',
        email: 'swati@vistar.com',
        fullName: 'Swati Raghunath Kotkar',
        role: UserRole.hr,
        organizationId: _orgId,
      ),
    ),
    'sagar@vistar.com': _MockAccount(
      password: 'password123',
      user: User(
        id: '5',
        email: 'sagar@vistar.com',
        fullName: 'Sagar Ananda Sasane',
        role: UserRole.finance,
        organizationId: _orgId,
      ),
    ),
  };

  @override
  Future<User> login({
    required String email,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final account = _accounts[email.trim().toLowerCase()];
    if (account == null || account.password != password) {
      throw const AuthException(
        'The email or password you entered is incorrect.',
        code: 'INVALID_CREDENTIALS',
      );
    }
    _currentUser = account.user;
    return account.user;
  }

  @override
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _currentUser = null;
  }

  @override
  Future<User?> getCurrentUser() async => _currentUser;

  @override
  Future<User?> refreshCurrentUser() async => _currentUser;
}

class _MockAccount {
  final String password;
  final User user;
  const _MockAccount({required this.password, required this.user});
}
