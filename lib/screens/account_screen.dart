import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../services/loading_service.dart';
import '../utils/toast_utils.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _signInFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  final _signInEmailController = TextEditingController();
  final _signInPasswordController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerPasswordConfirmController = TextEditingController();

  bool _isSignInExpanded = false;
  bool _isRegisterExpanded = false;

  @override
  void dispose() {
    _signInEmailController.dispose();
    _signInPasswordController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerPasswordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_signInFormKey.currentState!.validate()) return;

    try {
      LoadingService.show(message: 'サインイン中…');
      final authService = AuthService();
      await authService.signInWithEmail(
        _signInEmailController.text.trim(),
        _signInPasswordController.text,
      );
      await LoadingService.hide(withSuccess: true);

      if (!mounted) return;
      ToastUtils.showSuccess('サインインしました');
      _signInEmailController.clear();
      _signInPasswordController.clear();
      setState(() => _isSignInExpanded = false);
    } catch (e) {
      await LoadingService.hide(withSuccess: false);
      if (!mounted) return;
      ToastUtils.showError('サインインに失敗しました: $e');
    }
  }

  Future<void> _register() async {
    if (!_registerFormKey.currentState!.validate()) return;

    if (_registerPasswordController.text != _registerPasswordConfirmController.text) {
      ToastUtils.showError('パスワードが一致しません');
      return;
    }

    try {
      LoadingService.show(message: 'アカウント登録中…');
      final authService = AuthService();
      await authService.registerWithEmail(
        _registerEmailController.text.trim(),
        _registerPasswordController.text,
      );
      await LoadingService.hide(withSuccess: true);

      if (!mounted) return;
      ToastUtils.showSuccess('アカウント登録が完了しました');
      _registerEmailController.clear();
      _registerPasswordController.clear();
      _registerPasswordConfirmController.clear();
      setState(() => _isRegisterExpanded = false);
    } catch (e) {
      await LoadingService.hide(withSuccess: false);
      if (!mounted) return;
      ToastUtils.showError('アカウント登録に失敗しました: $e');
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('サインアウト'),
          content: const Text('サインアウトしますか？\n匿名アカウントに戻り、アプリが再起動されます。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('サインアウト'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      LoadingService.show(message: 'サインアウト中…');
      final authService = AuthService();
      await authService.signOutAndStayAnonymous();
      await LoadingService.hide(withSuccess: true);

      if (!mounted) return;

      // ホーム画面に戻り、全プロバイダをリセット
      // Riverpodのプロバイダは自動的にauth状態を監視して更新される
      context.go('/');

      // 成功メッセージ
      ToastUtils.showSuccess('サインアウトしました');
    } catch (e) {
      await LoadingService.hide(withSuccess: false);
      if (!mounted) return;
      ToastUtils.showError('サインアウトに失敗しました');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isAnonymous = user?.isAnonymous ?? true;
    final email = user?.email;

    return Scaffold(
      appBar: AppBar(
        title: const Text('アカウント設定'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 現在のアカウント状態
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '現在のアカウント',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        isAnonymous ? Icons.person_outline : Icons.person,
                        size: 32,
                        color: isAnonymous ? Colors.grey : Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAnonymous ? '匿名ユーザー' : 'メールアドレスでログイン',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (email != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                email,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!isAnonymous) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _signOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('サインアウト'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 匿名ユーザーの場合のみ表示
          if (isAnonymous) ...[
            const Text(
              'メールアドレスでアカウントを登録すると、端末間でデータを同期できます。',
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 16),

            // サインイン
            Card(
              child: ExpansionTile(
                title: const Text('既にアカウントをお持ちの方'),
                initiallyExpanded: _isSignInExpanded,
                onExpansionChanged: (expanded) {
                  setState(() => _isSignInExpanded = expanded);
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _signInFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _signInEmailController,
                            decoration: const InputDecoration(
                              labelText: 'メールアドレス',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.email),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'メールアドレスを入力してください';
                              }
                              if (!val.contains('@')) {
                                return '有効なメールアドレスを入力してください';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _signInPasswordController,
                            decoration: const InputDecoration(
                              labelText: 'パスワード',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.lock),
                            ),
                            obscureText: true,
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'パスワードを入力してください';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _signIn,
                            child: const Text('サインイン'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 新規登録
            Card(
              child: ExpansionTile(
                title: const Text('新規アカウント登録'),
                initiallyExpanded: _isRegisterExpanded,
                onExpansionChanged: (expanded) {
                  setState(() => _isRegisterExpanded = expanded);
                },
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _registerFormKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _registerEmailController,
                            decoration: const InputDecoration(
                              labelText: 'メールアドレス',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.email),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'メールアドレスを入力してください';
                              }
                              if (!val.contains('@')) {
                                return '有効なメールアドレスを入力してください';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _registerPasswordController,
                            decoration: const InputDecoration(
                              labelText: 'パスワード',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.lock),
                              helperText: '6文字以上',
                            ),
                            obscureText: true,
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'パスワードを入力してください';
                              }
                              if (val.length < 6) {
                                return 'パスワードは6文字以上で入力してください';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _registerPasswordConfirmController,
                            decoration: const InputDecoration(
                              labelText: 'パスワード(確認)',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            obscureText: true,
                            validator: (val) {
                              if (val == null || val.isEmpty) {
                                return 'パスワード(確認)を入力してください';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _register,
                            child: const Text('アカウント登録'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
