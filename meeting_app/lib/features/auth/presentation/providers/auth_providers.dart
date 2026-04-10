import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/supabase_auth_repository.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository();
});

final authStateChangesProvider = StreamProvider<AppUser?>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return repository.authStateChanges();
});

final authActionsProvider = Provider<AuthActions>((ref) {
  return AuthActions(ref.watch(authRepositoryProvider));
});

final class AuthActions {
  const AuthActions(this._repository);

  final AuthRepository _repository;

  Future<void> signIn({required String email, required String password}) {
    return _repository.signInWithEmail(email: email, password: password);
  }

  Future<void> signOut() {
    return _repository.signOut();
  }
}
