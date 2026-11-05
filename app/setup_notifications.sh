#!/usr/bin/env bash
# Step 4 setup for Bill Radar: packages + Android config for reminders.
# Run from ~/bill_remainder/app :  bash setup_notifications.sh
set -e

if [ ! -f pubspec.yaml ] || [ ! -d android ]; then
  echo "Run this inside ~/bill_remainder/app"; exit 1
fi

echo "1/3 packages"
flutter pub add flutter_local_notifications:^19.4.0 timezone:^0.10.0

G=android/app/build.gradle.kts
M=android/app/src/main/AndroidManifest.xml
cp "$G" "$G.bak"; cp "$M" "$M.bak"

echo "2/3 $G"
if ! grep -q "isCoreLibraryDesugaringEnabled" "$G"; then
  sed -i 's/^\( *\)compileOptions {/\1compileOptions {\n\1    isCoreLibraryDesugaringEnabled = true/' "$G"
fi
if ! grep -q "desugar_jdk_libs" "$G"; then
  cat >> "$G" <<'EOF'

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
EOF
fi

echo "3/3 $M"
if ! grep -q "POST_NOTIFICATIONS" "$M"; then
  sed -i '0,/^\( *\)<application/s//\1<uses-permission android:name="android.permission.POST_NOTIFICATIONS"\/>\n\1<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"\/>\n\1<application/' "$M"
fi
if ! grep -q "ScheduledNotificationReceiver" "$M"; then
  sed -i 's|^\( *\)</application>|\1    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />\n\1    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n\1        <intent-filter>\n\1            <action android:name="android.intent.action.BOOT_COMPLETED"/>\n\1            <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>\n\1        </intent-filter>\n\1    </receiver>\n\1</application>|' "$M"
fi

echo
echo "Check (each should print at least one line):"
grep -n "isCoreLibraryDesugaringEnabled" "$G"
grep -n "desugar_jdk_libs" "$G"
grep -n "POST_NOTIFICATIONS" "$M"
grep -n "ScheduledNotificationBootReceiver" "$M"
echo
echo "Done. Backups: $G.bak and $M.bak"
