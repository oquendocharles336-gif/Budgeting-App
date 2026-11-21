package com.budgeting.bugeting_app;

import androidx.core.content.FileProvider;

/**
 * Shares the downloaded update APK (app cache, "updates" folder only) with
 * Android's package installer. Its own class so it never clashes with a
 * FileProvider declared by a plugin.
 */
public class UpdateFileProvider extends FileProvider {
}
