import 'dart:async';

import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

final class MockAuthRepository implements AuthRepository {
  MockAuthRepository();

  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _currentUser;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _currentUser;
    yield* _controller.stream;
  }

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final user = AppUser(id: 'local-user-1', email: email);
    _currentUser = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _controller.add(null);
  }

  void dispose() {
    _controller.close();
  }
}
