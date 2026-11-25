// lib/widgets/new_invoice_menu.dart
//
// 🪟 كليك يمين (أو ضغطة مطوّلة باللمس) على زر «إنشاء فاتورة»:
//   • فتح إنشاء فاتورة — كالضغطة العادية (تُجلب الفاتورة المفتوحة).
//   • فاتورة جديدة في نافذة منفصلة — واجهة مستقلة تماماً بجانب المفتوحة، كما تفتح
//     «سجل الديون» في نافذة و«إنشاء فاتورة» في أخرى. لكل نافذة مسودتها المحفوظة،
//     والكميات بينها محجوزة (ما في فاتورة لا يُباع في الأخرى).
// النوافذ تُسحب وتُكبّر وتُلصق بنصف الشاشة من شريط عنوانها.

import 'package:flutter/material.dart';

import '../models/app_user.dart' show AppPermissions;
import '../screens/create_invoice_screen.dart';
import '../services/auth_service.dart';
import 'popup_screens.dart';

class NewInvoiceMenu {
  NewInvoiceMenu._();

  /// يفتح «إنشاء فاتورة» في نافذة منفصلة جديدة دائماً.
  static void openNewWindow(NavigatorState nav, BuildContext messages) {
    if (!AuthService().hasPermission(AppPermissions.createInvoice)) {
      ScaffoldMessenger.maybeOf(messages)
          ?.showSnackBar(const SnackBar(content: Text('ليس لديك صلاحية إنشاء فاتورة')));
      return;
    }
    final slot = CreateInvoiceScreen.claimSlot();
    if (slot == null) {
      ScaffoldMessenger.maybeOf(messages)?.showSnackBar(
          const SnackBar(content: Text('مفتوحة 8 فواتير — احفظ أو أغلق واحدة أولاً')));
      return;
    }
    nav.pushNamed('/create_invoice', arguments: PopupNewWindow(data: slot, label: 'فاتورة ${slot.substring(1)}'));
  }

  /// قائمة الكليك يمين عند [globalPos]. [openNormal] = الضغطة العادية على الزر.
  static Future<void> show(
    BuildContext context,
    Offset globalPos, {
    required NavigatorState nav,
    required VoidCallback openNormal,
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final size = overlay?.size ?? MediaQuery.sizeOf(context);
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, size.width - globalPos.dx, size.height - globalPos.dy),
      items: const [
        PopupMenuItem(
          value: 'open',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.receipt_long_rounded, color: Color(0xFF3F51B5)),
            title: Text('فتح إنشاء فاتورة'),
          ),
        ),
        PopupMenuItem(
          value: 'new',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.open_in_new_rounded, color: Color(0xFF0F766E)),
            title: Text('فاتورة جديدة في نافذة منفصلة'),
            subtitle: Text('واجهة مستقلة بجانب المفتوحة'),
          ),
        ),
      ],
    );
    if (v == 'open') openNormal();
    if (v == 'new' && context.mounted) openNewWindow(nav, context);
  }
}
