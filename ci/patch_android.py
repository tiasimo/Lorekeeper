"""Ritocca il progetto Android generato da `flutter create` in CI."""
import os, re

M = 'android/app/src/main/AndroidManifest.xml'
m = open(M).read()
m = m.replace('android:label="lorekeeper"', 'android:label="Lorekeeper"')
perms = ['INTERNET', 'POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED']
for p in perms:
    tag = f'<uses-permission android:name="android.permission.{p}"/>'
    if tag not in m:
        m = m.replace('<application', tag + '\n    <application', 1)
receivers = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    </application>'''
if 'ScheduledNotificationReceiver' not in m:
    m = m.replace('</application>', receivers.lstrip('\n'), 1)
open(M, 'w').write(m)

# Desugaring richiesto da flutter_local_notifications
kts = 'android/app/build.gradle.kts'
groovy = 'android/app/build.gradle'
if os.path.exists(kts):
    g = open(kts).read()
    if 'isCoreLibraryDesugaringEnabled' not in g:
        g = re.sub(r'compileOptions\s*\{', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', g, count=1)
    if 'desugar_jdk_libs' not in g:
        g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    open(kts, 'w').write(g)
elif os.path.exists(groovy):
    g = open(groovy).read()
    if 'coreLibraryDesugaringEnabled' not in g:
        g = re.sub(r'compileOptions\s*\{', 'compileOptions {\n        coreLibraryDesugaringEnabled true', g, count=1)
    if 'desugar_jdk_libs' not in g:
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    open(groovy, 'w').write(g)
print(open(M).read())
