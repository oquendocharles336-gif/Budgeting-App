package com.budgeting.bugeting_app;

import android.Manifest;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;

import androidx.annotation.NonNull;

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
 */
public class MainActivity extends FlutterFragmentActivity {
    private static final String CHANNEL = "pitaka/sms";
    private static final int SMS_PERMISSION_REQUEST = 4242;
    private static final int MAX_MESSAGES = 2000;

    private MethodChannel.Result pendingPermissionResult;

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
