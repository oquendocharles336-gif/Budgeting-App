# SQLCipher (sqflite_sqlcipher) is called through JNI; R8 must not strip it.
-keep class net.zetetic.database.** { *; }
-keep class net.sqlcipher.** { *; }
-dontwarn net.sqlcipher.**
