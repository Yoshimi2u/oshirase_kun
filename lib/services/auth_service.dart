import 'package:firebase_auth/firebase_auth.dart';

/// Firebase Authentication サービス（匿名/メールパスワード対応）
/// 既存コード互換のため、静的APIも提供する単一クラスに統合。
class AuthService {
  static final FirebaseAuth _sAuth = FirebaseAuth.instance;
  final FirebaseAuth _auth;

  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  // ----- 静的（互換用） -----
  static Future<User?> signInAnonymouslyIfNeeded() async {
    final currentUser = _sAuth.currentUser;
    if (currentUser != null) return currentUser;
    final userCredential = await _sAuth.signInAnonymously();
    return userCredential.user;
  }

  static User? get currentUserStatic => _sAuth.currentUser;

  // ----- インスタンスAPI -----
  Stream<User?> authStateChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> ensureSignedInAnonymously() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  /// 匿名→メール/パスワードへリンク（UID維持）or 新規登録
  Future<UserCredential> registerOrLinkEmailPassword(String email, String password) async {
    final cred = EmailAuthProvider.credential(email: email, password: password);
    final user = _auth.currentUser;
    if (user != null && user.isAnonymous) {
      return await user.linkWithCredential(cred);
    }
    if (user == null) {
      return await _auth.createUserWithEmailAndPassword(email: email, password: password);
    }
    throw FirebaseAuthException(code: 'already-registered', message: 'すでにメールアドレスでサインイン済みです');
  }

  Future<UserCredential> signIn(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOutAndStayAnonymous() async {
    await _auth.signOut();
    await _auth.signInAnonymously();
  }

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }
}
