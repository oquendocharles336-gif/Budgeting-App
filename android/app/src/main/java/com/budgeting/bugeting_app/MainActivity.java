package com.budgeting.bugeting_app;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.WindowManager;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.content.FileProvider;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/**
 * FlutterFragmentActivity is required by local_auth (biometric prompt).
 *
 * Also hosts a tiny "pitaka/sms" MethodChannel that reads the SMS inbox on
 * the device. Messages are returned to Dart for local parsing only; nothing
 * is sent over the network.
 *
 * And "pitaka/update": hands an APK the app downloaded itself (from the
 * GitHub release) to Android's package installer, so updating never needs
 * the browser. Android still shows its own "Update this app?" screen, and the
 * first time asks to allow "Install unknown apps" for Pitaka.
 */
public class MainActivity extends FlutterFragmentActivity {
    private static final String CHANNEL = "pitaka/sms";
    private static final int SMS_PERMISSION_REQUEST = 4242;
    private static final int MAX_MESSAGES = 2000;

    private MethodChannel.Result pendingPermissionResult;

    private static final String UPDATE_CHANNEL = "pitaka/update";
    private static final int INSTALL_REQUEST = 4243;
    private static final int UNKNOWN_SOURCES_REQUEST = 4244;
    private MethodChannel.Result pendingInstallResult;
    private String pendingApkPath;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        // Hide the app's contents in the Recent apps preview and block
        // screenshots / screen recording, so balances aren't exposed.
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE);
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "hasPermission":
                            result.success(hasSmsPermission());
                            break;
                        case "requestPermission":
                            requestSmsPermission(result);
                            break;
                        case "readInbox": {
                            Number since = call.argument("since");
                            Number limit = call.argument("limit");
                            readInbox(
                                    since == null ? 0L : since.longValue(),
                                    limit == null ? 500 : Math.min(limit.intValue(), MAX_MESSAGES),
                                    result);
                            break;
                        }
                        default:
                            result.notImplemented();
                    }
                });
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), UPDATE_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "canInstall":
                            result.success(canInstallApks());
                            break;
                        case "installApk":
                            installApk(call.argument("path"), result);
                            break;
                        default:
                            result.notImplemented();
                    }
                });
    }

    // ---------------------------------------------------------------------
    // In-app update: install a downloaded APK
    // ---------------------------------------------------------------------

    private boolean canInstallApks() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true;
        return getPackageManager().canRequestPackageInstalls();
    }

    private void installApk(String path, MethodChannel.Result result) {
        if (pendingInstallResult != null) {
            result.error("busy", "The installer is already open", null);
            return;
        }
        if (path == null || !new File(path).isFile()) {
            result.error("missing", "The downloaded update was not found", null);
            return;
        }
        pendingInstallResult = result;
        pendingApkPath = path;
        if (!canInstallApks()) {
            // First time: let the user allow "Install unknown apps" for Pitaka,
            // then come back here (onActivityResult) and open the installer.
            try {
                Intent settings = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + getPackageName()));
                startActivityForResult(settings, UNKNOWN_SOURCES_REQUEST);
            } catch (Exception e) {
                finishInstall("permission_denied");
            }
            return;
        }
        launchInstaller();
    }

    @SuppressWarnings("deprecation") // ACTION_INSTALL_PACKAGE still returns a result on every Android version.
    private void launchInstaller() {
        try {
            File apk = new File(pendingApkPath);
            Uri uri = FileProvider.getUriForFile(this, getPackageName() + ".updates.fileprovider", apk);
            Intent install = new Intent(Intent.ACTION_INSTALL_PACKAGE);
            install.setData(uri);
            install.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            install.putExtra(Intent.EXTRA_RETURN_RESULT, true);
            startActivityForResult(install, INSTALL_REQUEST);
        } catch (Exception e) {
            if (pendingInstallResult != null) {
                pendingInstallResult.error("install_failed", e.getMessage(), null);
                pendingInstallResult = null;
            }
        }
    }

    private void finishInstall(String outcome) {
        if (pendingInstallResult == null) return;
        pendingInstallResult.success(outcome);
        pendingInstallResult = null;
        pendingApkPath = null;
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == UNKNOWN_SOURCES_REQUEST) {
            if (pendingInstallResult == null) return;
            if (canInstallApks()) {
                launchInstaller();
            } else {
                finishInstall("permission_denied");
            }
        } else if (requestCode == INSTALL_REQUEST) {
            // On success Android usually restarts the app before this runs.
            if (resultCode == Activity.RESULT_OK) {
                finishInstall("installed");
            } else if (resultCode == Activity.RESULT_CANCELED) {
                finishInstall("cancelled");
            } else {
                finishInstall("failed");
            }
        }
    }

    private boolean hasSmsPermission() {
        return checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED;
    }

    private void requestSmsPermission(MethodChannel.Result result) {
        if (hasSmsPermission()) {
            result.success(true);
            return;
        }
        if (pendingPermissionResult != null) {
            result.error("busy", "A permission request is already in progress", null);
            return;
        }
        pendingPermissionResult = result;
        requestPermissions(new String[]{Manifest.permission.READ_SMS}, SMS_PERMISSION_REQUEST);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != SMS_PERMISSION_REQUEST || pendingPermissionResult == null) return;
        boolean granted = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        pendingPermissionResult.success(granted);
        pendingPermissionResult = null;
    }

    private void readInbox(long sinceMillis, int limit, MethodChannel.Result result) {
        if (!hasSmsPermission()) {
            result.error("no_permission", "READ_SMS permission not granted", null);
            return;
        }
        // Query off the UI thread; reply on the UI thread.
        new Thread(() -> {
            List<Map<String, Object>> messages = new ArrayList<>();
            String[] projection = {"_id", "address", "body", "date"};
            try (Cursor c = getContentResolver().query(
                    Uri.parse("content://sms/inbox"),
                    projection,
                    "date >= ?",
                    new String[]{String.valueOf(sinceMillis)},
                    "date DESC")) {
                if (c != null) {
                    int idIdx = c.getColumnIndexOrThrow("_id");
                    int addressIdx = c.getColumnIndexOrThrow("address");
                    int bodyIdx = c.getColumnIndexOrThrow("body");
                    int dateIdx = c.getColumnIndexOrThrow("date");
                    while (c.moveToNext() && messages.size() < limit) {
                        Map<String, Object> m = new HashMap<>();
                        m.put("id", c.getString(idIdx));
                        m.put("address", c.getString(addressIdx));
                        m.put("body", c.getString(bodyIdx));
                        m.put("date", c.getLong(dateIdx));
                        messages.add(m);
                    }
                }
                runOnUiThread(() -> result.success(messages));
            } catch (Exception e) {
                runOnUiThread(() -> result.error("read_failed", e.getMessage(), null));
            }
        }).start();
    }
}
