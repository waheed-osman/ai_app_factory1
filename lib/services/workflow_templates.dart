import '../models/build_models.dart';

/// قوالب ملفات GitHub Actions.
/// كل منصة لها ملف مستقل ويُشغَّل يدوياً (workflow_dispatch) من التطبيق،
/// حتى لا يتكرر التشغيل عند كل دفع (push).
class WorkflowTemplates {
  WorkflowTemplates._();

  static const String apkPath = '.github/workflows/build_apk.yml';
  static const String webPath = '.github/workflows/build_web.yml';

  static String pathFor(SingleTarget t) =>
      t == SingleTarget.apk ? apkPath : webPath;

  static String forTarget(
    SingleTarget t, {
    required String projectName,
    required String repoName,
    bool strictTests = false,
    bool publishPages = true,
  }) {
    return t == SingleTarget.apk
        ? apk(projectName: projectName, strictTests: strictTests)
        : web(
            projectName: projectName,
            repoName: repoName,
            strictTests: strictTests,
            publishPages: publishPages,
          );
  }

  static String apk({required String projectName, bool strictTests = false}) {
    return _apkTemplate
        .replaceAll('__PROJECT_NAME__', projectName)
        .replaceAll(
          '__TEST_CONTINUE__',
          strictTests ? '' : '        continue-on-error: true',
        );
  }

  static String web({
    required String projectName,
    required String repoName,
    bool strictTests = false,
    bool publishPages = true,
  }) {
    final baseHref = publishPages ? '/$repoName/' : '/';
    final deploy = publishPages ? _pagesDeployStep : '';
    return _webTemplate
        .replaceAll('__PROJECT_NAME__', projectName)
        .replaceAll('__BASE_HREF__', baseHref)
        .replaceAll('__PAGES_STEP__', deploy)
        .replaceAll(
          '__TEST_CONTINUE__',
          strictTests ? '' : '        continue-on-error: true',
        );
  }

  static const String _apkTemplate = r'''
name: Build Flutter APK
on:
  workflow_dispatch:
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 40
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - name: Generate Android platform files
        run: |
          HAD_WIDGET_TEST=0
          if [ -f test/widget_test.dart ]; then HAD_WIDGET_TEST=1; fi
          flutter create . --platforms=android --project-name __PROJECT_NAME__ --org com.example
          if [ "$HAD_WIDGET_TEST" = "0" ]; then rm -f test/widget_test.dart; fi
      - name: Allow internet access in release builds
        run: |
          python3 - <<'PY'
          import re
          path = "android/app/src/main/AndroidManifest.xml"
          text = open(path, encoding="utf-8").read()
          if "android.permission.INTERNET" not in text:
              tag = '<uses-permission android:name="android.permission.INTERNET"/>'
              text = re.sub(r"(<manifest[^>]*>)", lambda m: m.group(1) + "\n    " + tag, text, count=1)
          open(path, "w", encoding="utf-8").write(text)
          PY
      - name: Install dependencies
        run: flutter pub get
      - name: Analyze
        run: flutter analyze --no-fatal-infos --no-fatal-warnings
        continue-on-error: true
      - name: Test
        run: if [ -d test ]; then flutter test; else echo "No tests found"; fi
__TEST_CONTINUE__
      - name: Build release APK
        run: flutter build apk --release
      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: apk
          path: build/app/outputs/flutter-apk/app-release.apk
''';

  static const String _pagesDeployStep = r'''
      - name: Deploy to GitHub Pages branch
        uses: peaceiris/actions-gh-pages@v4
        continue-on-error: true
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./build/web
          publish_branch: gh-pages
''';

  static const String _webTemplate = r'''
name: Build Flutter Web
on:
  workflow_dispatch:
permissions:
  contents: write
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 40
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - name: Generate Web platform files
        run: |
          HAD_WIDGET_TEST=0
          if [ -f test/widget_test.dart ]; then HAD_WIDGET_TEST=1; fi
          flutter create . --platforms=web --project-name __PROJECT_NAME__ --org com.example
          if [ "$HAD_WIDGET_TEST" = "0" ]; then rm -f test/widget_test.dart; fi
      - name: Install dependencies
        run: flutter pub get
      - name: Analyze
        run: flutter analyze --no-fatal-infos --no-fatal-warnings
        continue-on-error: true
      - name: Test
        run: if [ -d test ]; then flutter test; else echo "No tests found"; fi
__TEST_CONTINUE__
      - name: Build release Web
        run: flutter build web --release --base-href "__BASE_HREF__"
      - name: Upload Web build
        uses: actions/upload-artifact@v4
        with:
          name: web
          path: build/web
__PAGES_STEP__''';
}
