/// E-wallet / bank apps whose payment notifications Pitaka can read for
/// free, on the phone (Android "Notification access"). Stored by [id] in
/// `cards.notify_app`.
enum WalletApp {
  maya('maya', 'Maya', 'com.paymaya'),
  gcash('gcash', 'GCash', 'com.globe.gcash.android'),
  maribank('maribank', 'MariBank', 'ph.seabank.seabank'),
  bdoPay('bdo_pay', 'BDO Pay', 'www.pay.bdo.com.ph');

  const WalletApp(this.id, this.label, this.packageName);

  /// Saved in the database.
  final String id;
  final String label;

  /// The Android app whose notifications are read.
  final String packageName;

  static WalletApp? fromId(String? id) {
    for (final a in WalletApp.values) {
      if (a.id == id) return a;
    }
    return null;
  }

  static WalletApp? forPackage(String packageName) {
    for (final a in WalletApp.values) {
      if (a.packageName == packageName) return a;
    }
    return null;
  }

  /// A good first choice from the nickname ("Maya Savings" -> Maya).
  static WalletApp? guess(String nickname) {
    final n = nickname.toLowerCase();
    if (n.contains('maya') || n.contains('paymaya')) return WalletApp.maya;
    if (n.contains('gcash')) return WalletApp.gcash;
    if (n.contains('mari') || n.contains('seabank')) return WalletApp.maribank;
    if (n.contains('bdo')) return WalletApp.bdoPay;
    return null;
  }
}
