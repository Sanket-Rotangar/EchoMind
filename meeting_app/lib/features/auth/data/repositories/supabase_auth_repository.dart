import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

final class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Stream<AppUser?> authStateChanges() {
    return _client.auth.onAuthStateChange
        .map((event) {
          return _mapUser(event.session?.user);
        })
        .startWith(_mapUser(_client.auth.currentUser));
  }

  @override
  Future<AppUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw StateError('Sign-in succeeded but user was missing in response');
    }

    return _mapUser(user)!;
  }

  @override
  Future<void> signOut() {
    return _client.auth.signOut();
  }

  AppUser? _mapUser(User? user) {
    if (user == null) {
      return null;
    }

    final email = user.email;
    if (email == null || email.isEmpty) {
      throw StateError('Authenticated user does not contain a valid email');
    }

    return AppUser(id: user.id, email: email);
  }
}

extension<T> on Stream<T> {
  Stream<T> startWith(T value) async* {
    yield value;
    yield* this;
  }
}
