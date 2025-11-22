import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// アプリ共通のダイアログテーマ
class AppDialogTheme {
  static const dialogShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );

  static const titleTextStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
  );

  static const contentTextStyle = TextStyle(
    fontSize: 15,
    height: 1.5,
  );

  static ButtonStyle primaryButtonStyle(Color color) => ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      );

  static ButtonStyle textButtonStyle() => TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontSize: 16),
      );
}

/// 削除確認ダイアログ（危険な操作用）
class DeleteConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String? subMessage;
  final String confirmText;
  final VoidCallback? onConfirm;

  const DeleteConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.subMessage,
    this.confirmText = '削除する',
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: AppDialogTheme.dialogShape,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_rounded, color: Colors.red, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: AppDialogTheme.titleTextStyle,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          if (subMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              subMessage!,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: AppDialogTheme.textButtonStyle(),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context, true);
            onConfirm?.call();
          },
          style: AppDialogTheme.primaryButtonStyle(Colors.red),
          child: Text(confirmText),
        ),
      ],
    );
  }

  /// 表示用のヘルパーメソッド
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String? subMessage,
    String confirmText = '削除する',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => DeleteConfirmationDialog(
        title: title,
        message: message,
        subMessage: subMessage,
        confirmText: confirmText,
      ),
    );
  }
}

/// 編集方法選択ダイアログ（繰り返しタスク用）
class EditMethodDialog extends StatelessWidget {
  const EditMethodDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: AppDialogTheme.dialogShape,
      title: const Row(
        children: [
          Icon(Icons.edit_calendar, color: Colors.blue, size: 28),
          SizedBox(width: 12),
          Text('編集方法を選択', style: AppDialogTheme.titleTextStyle),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'この予定は繰り返し設定があります。\nどのように編集しますか?',
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 20),
          _EditOptionCard(
            icon: Icons.event,
            title: 'このタスクのみ編集',
            subtitle: '他の予定には影響しません',
            color: Colors.orange,
            onTap: () => Navigator.pop(context, 'single'),
          ),
          const SizedBox(height: 12),
          _EditOptionCard(
            icon: Icons.event_repeat,
            title: '今後すべてを編集',
            subtitle: '繰り返しの設定を変更します',
            color: Colors.blue,
            onTap: () => Navigator.pop(context, 'future'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          style: AppDialogTheme.textButtonStyle(),
          child: const Text('キャンセル'),
        ),
      ],
    );
  }

  /// 表示用のヘルパーメソッド
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (context) => const EditMethodDialog(),
    );
  }
}

/// 編集オプションカード
class _EditOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _EditOptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.3), width: 2),
          borderRadius: BorderRadius.circular(12),
          color: color.withOpacity(0.05),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 16),
          ],
        ),
      ),
    );
  }
}

/// 確認ダイアログ（通常の操作用）
class ConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;
  final String cancelText;
  final Color? confirmColor;
  final IconData? icon;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmText = 'OK',
    this.cancelText = 'キャンセル',
    this.confirmColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: AppDialogTheme.dialogShape,
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: confirmColor ?? Colors.blue, size: 28),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(title, style: AppDialogTheme.titleTextStyle),
          ),
        ],
      ),
      content: Text(message, style: AppDialogTheme.contentTextStyle),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: AppDialogTheme.textButtonStyle(),
          child: Text(cancelText),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: AppDialogTheme.primaryButtonStyle(confirmColor ?? Colors.blue),
          child: Text(confirmText),
        ),
      ],
    );
  }

  /// 表示用のヘルパーメソッド
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'OK',
    String cancelText = 'キャンセル',
    Color? confirmColor,
    IconData? icon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
        confirmColor: confirmColor,
        icon: icon,
      ),
    );
  }
}

/// 成功ダイアログ（招待コード表示など）
class SuccessDialog extends StatelessWidget {
  final String title;
  final String message;
  final Widget? content;
  final List<Widget>? actions;

  const SuccessDialog({
    super.key,
    required this.title,
    required this.message,
    this.content,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: AppDialogTheme.dialogShape,
      contentPadding: EdgeInsets.zero,
      content: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark ? [Colors.grey[850]!, Colors.grey[900]!] : [Colors.blue[50]!, Colors.blue[100]!],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(isDark ? 0.2 : 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      color: isDark ? Colors.green[300] : Colors.green,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (content != null) ...[
                    const SizedBox(height: 20),
                    content!,
                  ],
                ],
              ),
            ),
            if (actions != null && actions!.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.white,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: _buildActionButtons(actions!, isDark),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActionButtons(List<Widget> actions, bool isDark) {
    final buttons = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      buttons.add(Expanded(child: actions[i]));
      if (i < actions.length - 1) {
        buttons.add(Container(
          width: 1,
          height: 40,
          color: isDark ? Colors.grey[700] : Colors.grey[300],
        ));
      }
    }
    return buttons;
  }
}

/// 招待コード表示ダイアログ
class InviteCodeDialog extends StatelessWidget {
  final String inviteCode;
  final VoidCallback onCopy;

  const InviteCodeDialog({
    super.key,
    required this.inviteCode,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SuccessDialog(
      title: 'グループを作成しました！',
      message: '',
      content: Column(
        children: [
          Text(
            '招待コード',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey[400] : Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[850] : Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              inviteCode,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: isDark ? Colors.blue[300] : Colors.blue,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'メンバーにこのコードを共有してください',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[400] : Colors.grey[700],
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: inviteCode));
            onCopy();
          },
          icon: const Icon(Icons.copy),
          label: const Text('コピー', style: TextStyle(fontSize: 16)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('閉じる', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  /// 表示用のヘルパーメソッド
  static Future<void> show(
    BuildContext context, {
    required String inviteCode,
    required VoidCallback onCopy,
  }) {
    return showDialog(
      context: context,
      builder: (context) => InviteCodeDialog(
        inviteCode: inviteCode,
        onCopy: onCopy,
      ),
    );
  }
}

/// 入力ダイアログ（テキスト入力用）
class InputDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String label;
  final String hint;
  final String? initialValue;
  final int? maxLength;
  final String confirmText;
  final IconData? icon;
  final Color? primaryColor;
  final String? Function(String?)? validator;

  const InputDialog({
    super.key,
    required this.title,
    this.message,
    required this.label,
    required this.hint,
    this.initialValue,
    this.maxLength,
    this.confirmText = '入力',
    this.icon,
    this.primaryColor,
    this.validator,
  });

  @override
  State<InputDialog> createState() => _InputDialogState();

  /// 表示用のヘルパーメソッド
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String? message,
    required String label,
    required String hint,
    String? initialValue,
    int? maxLength,
    String confirmText = '入力',
    IconData? icon,
    Color? primaryColor,
    String? Function(String?)? validator,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => InputDialog(
        title: title,
        message: message,
        label: label,
        hint: hint,
        initialValue: initialValue,
        maxLength: maxLength,
        confirmText: confirmText,
        icon: icon,
        primaryColor: primaryColor,
        validator: validator,
      ),
    );
  }
}

class _InputDialogState extends State<InputDialog> {
  late TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validate() {
    if (widget.validator != null) {
      setState(() {
        _errorText = widget.validator!(_controller.text);
      });
    }
  }

  void _onConfirm() {
    _validate();
    if (_errorText == null && _controller.text.trim().isNotEmpty) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.primaryColor ?? Colors.blue;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: AppDialogTheme.dialogShape,
      title: Row(
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, color: color, size: 28),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(widget.title, style: AppDialogTheme.titleTextStyle),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[
            Text(
              widget.message!,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              errorText: _errorText,
              prefixIcon: widget.icon != null ? Icon(widget.icon) : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: isDark ? Colors.grey[800] : Colors.grey[50],
            ),
            maxLength: widget.maxLength,
            autofocus: true,
            onChanged: (_) => _validate(),
            onSubmitted: (_) => _onConfirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: AppDialogTheme.textButtonStyle(),
          child: const Text('キャンセル'),
        ),
        ElevatedButton.icon(
          onPressed: _onConfirm,
          icon: const Icon(Icons.check),
          label: Text(widget.confirmText),
          style: AppDialogTheme.primaryButtonStyle(color),
        ),
      ],
    );
  }
}
