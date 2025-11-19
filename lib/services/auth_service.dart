import 'package:firebase_auth/firebase_auth.dart';
import '../repositories/user_profile_repository.dart';

/// Firebase Authentication サービス（匿名/メールパスワード対応）
/// 既存コード互換のため、静的APIも提供する単一クラスに統合。
class AuthService {
  static final FirebaseAuth _sAuth = FirebaseAuth.instance;
  final FirebaseAuth _auth;

  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  // ----- 静的(互換用) -----
  static Future<User?> signInAnonymouslyIfNeeded() async {
    final currentUser = _sAuth.currentUser;
    if (currentUser != null) return currentUser;
    final userCredential = await _sAuth.signInAnonymously();

    // 新規匿名ユーザーのプロフィールを作成
    // FCM初期化はMyApp._initializeUserDataで行われる
    if (userCredential.user != null) {
      final uid = userCredential.user!.uid;
      final userProfileRepository = UserProfileRepository();
      await userProfileRepository.createProfileIfNotExists(uid);
    }

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

  /// メールアドレスでサインイン
  /// 既に同じメールアドレスのアカウントがある場合は、そのアカウントでサインイン
  /// ない場合は、現在の匿名アカウントをメールアドレスアカウントにリンク
  Future<UserCredential> signInWithEmail(String email, String password) async {
    final currentUser = _auth.currentUser;

    // 既に同じメールアドレスでサインイン済みの場合
    if (currentUser != null && !currentUser.isAnonymous && currentUser.email == email) {
      throw FirebaseAuthException(
        code: 'already-signed-in',
        message: '既にこのメールアドレスでサインイン済みです',
      );
    }

    // 匿名ユーザーの場合、まずメールアドレスアカウントが存在するか確認
    if (currentUser != null && currentUser.isAnonymous) {
      try {
        // 既存のアカウントでサインイン試行
        final methods = await _auth.fetchSignInMethodsForEmail(email);

        if (methods.isNotEmpty) {
          // アカウントが存在する場合は、匿名データを破棄して既存アカウントでサインイン
          await _auth.signOut();
          return await _auth.signInWithEmailAndPassword(email: email, password: password);
        } else {
          // アカウントが存在しない場合は、匿名アカウントをリンク（新規登録と同じ）
          final credential = EmailAuthProvider.credential(email: email, password: password);
          final cred = await currentUser.linkWithCredential(credential);
          await cred.user?.sendEmailVerification();
          return cred;
        }
      } catch (e) {
        // エラーの場合は通常のサインインを試行
        await _auth.signOut();
        return await _auth.signInWithEmailAndPassword(email: email, password: password);
      }
    }

    // 匿名ユーザーでない場合は通常のサインイン
    return await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  /// メールアドレスで新規登録（エイリアス）
  Future<UserCredential> registerWithEmail(String email, String password) async {
    final currentUser = _auth.currentUser;

    // 匿名ユーザーの場合はリンク、そうでない場合は新規作成
    if (currentUser != null && currentUser.isAnonymous) {
      final credential = EmailAuthProvider.credential(email: email, password: password);
      final cred = await currentUser.linkWithCredential(credential);
      await cred.user?.sendEmailVerification();
      return cred;
    } else {
      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await cred.user?.sendEmailVerification();
      return cred;
    }
  }

  Future<void> signOutAndStayAnonymous() async {
    await _auth.signOut();
    final userCredential = await _auth.signInAnonymously();

    // 新しい匿名ユーザーのプロフィールを作成
    // FCM初期化はAuthStateの変更を検知して_initializeUserDataで行われる
    if (userCredential.user != null) {
      final uid = userCredential.user!.uid;
      final userProfileRepository = UserProfileRepository();
      await userProfileRepository.createProfileIfNotExists(uid);
    }
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
