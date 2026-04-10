import '../entities/app_user.dart';

abstract interface class AuthRepository {
  Stream<AppUser?> authStateChanges();

  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  });

  Future<void> signOut();
}
