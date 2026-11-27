/// E-wallet / bank apps whose payment notifications Pitaka can read for
/// free, on the phone (Android "Notification access"). Stored by [id] in
/// `cards.notify_app`.
enum WalletApp {
  maya('maya', 'Maya', 'com.paymaya', r'maya'),
  gcash('gcash', 'GCash', 'com.globe.gcash.android', r'g-?cash'),
  maribank('maribank', 'MariBank', 'ph.seabank.seabank', r'mari\s?bank|seabank'),
  bdoPay('bdo_pay', 'BDO Pay', 'www.pay.bdo.com.ph', r'bdo');

  const WalletApp(this.id, this.label, this.packageName, this._smsSender);

  /// Saved in the database.
  final String id;
  final String label;

  /// The Android app whose notifications are read.
  final String packageName;

  /// What the app's SMS sender id looks like ("GCash", "PayMaya").
  final String _smsSender;

  /// True when an SMS from [address] comes from this app.
  bool sentSms(String address) => RegExp(_smsSender, caseSensitive: false).hasMatch(address);

  /// The app an SMS sender belongs to, or null.
  static WalletApp? forSmsSender(String address) {
    for (final a in WalletApp.values) {
      if (a.sentSms(address)) return a;
    }
    return null;
  }

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
