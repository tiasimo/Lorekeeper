"""Backup automatico di Android e widget "Continua a leggere" (eseguito dopo patch_android.py)."""
import os

M = 'android/app/src/main/AndroidManifest.xml'
RES = 'android/app/src/main/res'
for d in ('xml', 'layout', 'drawable', 'values'):
    os.makedirs(f'{RES}/{d}', exist_ok=True)

# --- Backup su Google Drive: libreria, progressi, wiki, note e statistiche.
# Esclusi gli EPUB (troppo pesanti, si reimportano) e la chiave cifrata di Gemini.
RULES = """
    <include domain="root" path="app_flutter/lorekeeper/"/>
    <exclude domain="root" path="app_flutter/lorekeeper/books/"/>
    <exclude domain="root" path="app_flutter/lorekeeper/wiki/photos/"/>
    <exclude domain="root" path="app_flutter/lorekeeper/manga_dl/"/>
    <include domain="sharedpref" path="."/>
    <exclude domain="sharedpref" path="FlutterSecureStorage.xml"/>
"""
with open(f'{RES}/xml/backup_rules.xml', 'w') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n<full-backup-content>' + RULES + '</full-backup-content>\n')
with open(f'{RES}/xml/data_extraction_rules.xml', 'w') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n<data-extraction-rules>\n  <cloud-backup>' + RULES + '  </cloud-backup>\n  <device-transfer>' + RULES + '  </device-transfer>\n</data-extraction-rules>\n')

m = open(M).read()
if 'fullBackupContent' not in m:
    m = m.replace('<application', '<application\n        android:allowBackup="true"\n        android:usesCleartextTraffic="true"\n        android:fullBackupContent="@xml/backup_rules"\n        android:dataExtractionRules="@xml/data_extraction_rules"', 1)

# --- Widget
RECEIVER = """        <receiver android:name=".ContinueWidget" android:exported="true" android:label="Continua a leggere">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>
            </intent-filter>
            <meta-data android:name="android.appwidget.provider" android:resource="@xml/continue_widget_info"/>
        </receiver>
    </application>"""
if 'ContinueWidget' not in m:
    m = m.replace('</application>', RECEIVER, 1)
open(M, 'w').write(m)

with open(f'{RES}/xml/continue_widget_info.xml', 'w') as f:
    f.write("""<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="250dp"
    android:minHeight="110dp"
    android:targetCellWidth="4"
    android:targetCellHeight="2"
    android:resizeMode="horizontal|vertical"
    android:updatePeriodMillis="0"
    android:initialLayout="@layout/continue_widget"
    android:previewLayout="@layout/continue_widget"
    android:description="@string/continue_widget_desc"
    android:widgetCategory="home_screen"/>
""")

strings = f'{RES}/values/strings.xml'
line = '    <string name="continue_widget_desc">Riprendi il libro che stai leggendo</string>\n'
if os.path.exists(strings):
    sv = open(strings).read()
    if 'continue_widget_desc' not in sv:
        sv = sv.replace('</resources>', line + '</resources>')
    open(strings, 'w').write(sv)
else:
    open(strings, 'w').write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n' + line + '</resources>\n')

with open(f'{RES}/drawable/widget_bg.xml', 'w') as f:
    f.write("""<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#FAF7F2"/>
    <corners android:radius="22dp"/>
    <stroke android:width="1dp" android:color="#E6DED3"/>
</shape>
""")

with open(f'{RES}/layout/continue_widget.xml', 'w') as f:
    f.write("""<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/w_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/widget_bg"
    android:orientation="horizontal"
    android:padding="12dp"
    android:gravity="center_vertical">
    <ImageView
        android:id="@+id/w_cover"
        android:layout_width="58dp"
        android:layout_height="86dp"
        android:scaleType="centerCrop"
        android:src="@mipmap/ic_launcher"/>
    <LinearLayout
        android:layout_width="0dp"
        android:layout_height="wrap_content"
        android:layout_weight="1"
        android:layout_marginStart="12dp"
        android:orientation="vertical">
        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="CONTINUA A LEGGERE"
            android:textColor="#9A3F2B"
            android:textSize="10sp"
            android:textStyle="bold"
            android:letterSpacing="0.12"/>
        <TextView
            android:id="@+id/w_title"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:layout_marginTop="2dp"
            android:text="Lorekeeper"
            android:textColor="#2A2420"
            android:textSize="17sp"
            android:fontFamily="serif"
            android:textStyle="bold"
            android:maxLines="2"
            android:ellipsize="end"/>
        <TextView
            android:id="@+id/w_sub"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:text="Apri la tua libreria"
            android:textColor="#6B5F57"
            android:textSize="12sp"
            android:fontFamily="serif"
            android:maxLines="1"
            android:ellipsize="end"/>
        <ProgressBar
            android:id="@+id/w_progress"
            style="?android:attr/progressBarStyleHorizontal"
            android:layout_width="match_parent"
            android:layout_height="6dp"
            android:layout_marginTop="8dp"
            android:max="100"
            android:progress="0"
            android:progressTint="#9A3F2B"
            android:progressBackgroundTint="#E6DED3"/>
    </LinearLayout>
</LinearLayout>
""")

kt_dir = 'android/app/src/main/kotlin/com/tiasimo/lorekeeper'
os.makedirs(kt_dir, exist_ok=True)
with open(f'{kt_dir}/ContinueWidget.kt', 'w') as f:
    f.write("""package com.tiasimo.lorekeeper

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class ContinueWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: SharedPreferences) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.continue_widget)
            views.setTextViewText(R.id.w_title, widgetData.getString("title", "Lorekeeper"))
            views.setTextViewText(R.id.w_sub, widgetData.getString("sub", "Apri la tua libreria"))
            views.setProgressBar(R.id.w_progress, 100, widgetData.getInt("progress", 0), false)
            val cover = widgetData.getString("cover", null)
            if (cover != null) {
                try {
                    val opts = BitmapFactory.Options()
                    opts.inSampleSize = 4
                    val bmp = BitmapFactory.decodeFile(cover, opts)
                    if (bmp != null) views.setImageViewBitmap(R.id.w_cover, Bitmap.createScaledBitmap(bmp, 174, 258, true))
                } catch (e: Exception) {
                }
            }
            val intent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("lorekeeper://continua"))
            views.setOnClickPendingIntent(R.id.w_root, intent)
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
""")
print(open(M).read())

# ---------------------------------------------------------------------------
# Manga: motore delle estensioni di AnymeX (Mangayomi + Mihon/Aniyomi)
m = open(M).read()
extra_perms = ['QUERY_ALL_PACKAGES', 'REQUEST_DELETE_PACKAGES']
for perm in extra_perms:
    tag = f'<uses-permission android:name="android.permission.{perm}"/>'
    if tag not in m:
        m = m.replace('<application', tag + '\n    <application', 1)
open(M, 'w').write(m)

root_kts = 'android/build.gradle.kts'
if os.path.exists(root_kts):
    g = open(root_kts).read()
    if 'jitpack.io' not in g:
        g = g.replace('mavenCentral()', 'mavenCentral()\n        maven { url = uri("https://jitpack.io") }', 1)
    HOOK = '''// Plugin vecchi senza namespace e con Java diverso: li allineo (serve al motore delle estensioni)
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        try {
            val ns = android.javaClass.getMethod("getNamespace").invoke(android)
            if (ns == null) {
                android.javaClass.getMethod("setNamespace", String::class.java).invoke(android, project.group.toString())
            }
        } catch (e: Exception) {
        }
        try {
            android.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType).invoke(android, 36)
        } catch (e: Exception) {
        }
        try {
            val co = android.javaClass.getMethod("getCompileOptions").invoke(android)
            co.javaClass.getMethod("setSourceCompatibility", JavaVersion::class.java).invoke(co, JavaVersion.VERSION_17)
            co.javaClass.getMethod("setTargetCompatibility", JavaVersion::class.java).invoke(co, JavaVersion.VERSION_17)
        } catch (e: Exception) {
        }
    }
}

'''
    if 'getNamespace' not in g:
        anchor = 'subprojects {\n    project.evaluationDependsOn(":app")'
        g = g.replace(anchor, HOOK + anchor, 1) if anchor in g else HOOK + g
    open(root_kts, 'w').write(g)
    print(g)

app_kts = 'android/app/build.gradle.kts'
if os.path.exists(app_kts):
    g = open(app_kts).read()
    if 'OSGI-INF' not in g:
        g = g.replace('android {', 'android {\n    packaging {\n        resources {\n            excludes += "META-INF/versions/9/OSGI-INF/MANIFEST.MF"\n        }\n    }', 1)
    g = g.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
    open(app_kts, 'w').write(g)

props = 'android/gradle.properties'
pv = open(props).read() if os.path.exists(props) else ''
for line in ['kotlin.jvm.target.validation.mode=warning', 'android.enableJetifier=true']:
    if line.split('=')[0] not in pv:
        pv += '\n' + line
open(props, 'w').write(pv + '\n')
print(pv)

# ---------------------------------------------------------------------------
# Accesso ad AniList: il browser torna all'app con lorekeeper://anilist
m = open(M).read()
if 'flutter_web_auth_2.CallbackActivity' not in m:
    m = m.replace('</application>', """        <activity android:name="com.linusu.flutter_web_auth_2.CallbackActivity" android:exported="true">
            <intent-filter android:label="flutter_web_auth_2">
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="lorekeeper"/>
            </intent-filter>
        </activity>
    </application>""", 1)
    open(M, 'w').write(m)

# ---------------------------------------------------------------------------
# Icone delle scorciatoie (tenendo premuta l'icona dell'app)
SHORT = {
    'ic_shortcut_book': 'M4,5h7c1.1,0 2,0.9 2,2v12c0,-0.8 -0.9,-1.5 -2,-1.5H4V5zM20,5h-7c-1.1,0 -2,0.9 -2,2v12c0,-0.8 0.9,-1.5 2,-1.5h7V5z',
    'ic_shortcut_manga': 'M4,4h16v16H4V4zM4,11h16M12,4l-1.5,7M14,11l1.5,9',
    'ic_shortcut_add': 'M12,4v16M4,12h16',
}
for name, d in SHORT.items():
    with open(f'{RES}/drawable/{name}.xml', 'w') as f:
        f.write(f"""<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="48dp" android:height="48dp" android:viewportWidth="24" android:viewportHeight="24">
    <path android:pathData="M12,0a12,12 0 1,0 0.01,0z" android:fillColor="#9A3F2B"/>
    <group android:scaleX="0.6" android:scaleY="0.6" android:pivotX="12" android:pivotY="12">
        <path android:pathData="{d}" android:strokeColor="#FFF6EEDC" android:strokeWidth="2" android:fillColor="#00000000" android:strokeLineCap="round" android:strokeLineJoin="round"/>
    </group>
</vector>
""")
