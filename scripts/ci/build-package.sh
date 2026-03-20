#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SRC_DIR="$PROJECT_DIR/src"
BUILD_DIR="$PROJECT_DIR/build"

APP_NAME="${APP_NAME:-Sudo}"
APP_VERSION="${APP_VERSION:-1.0.0}"
MODULE_NAME="${MODULE_NAME:-com.sudo.app}"
MAIN_CLASS="${MAIN_CLASS:-com.sudo.Main}"
PACKAGE_TYPE="${PACKAGE_TYPE:?PACKAGE_TYPE is required}"

JAVAFX_SDK_DIR="${JAVAFX_SDK_DIR:?JAVAFX_SDK_DIR is required}"
PACKAGE_ICON="${PACKAGE_ICON:-}"
PACKAGE_VENDOR="${PACKAGE_VENDOR:-Panpan}"
PACKAGE_DESCRIPTION="${PACKAGE_DESCRIPTION:-Sudoku Game}"

if [[ "${OSTYPE:-}" == "msys"* || "${OSTYPE:-}" == "cygwin"* ]]; then
  if command -v cygpath >/dev/null 2>&1; then
    JAVA_HOME="$(cygpath -u "${JAVA_HOME:?JAVA_HOME is required}")"
  fi
fi

JAVA_HOME="${JAVA_HOME:?JAVA_HOME is required}"
JAVAC="$JAVA_HOME/bin/javac"
JAR="$JAVA_HOME/bin/jar"
JLINK="$JAVA_HOME/bin/jlink"
JPACKAGE="$JAVA_HOME/bin/jpackage"

if [[ ! -x "$JAVAC" || ! -x "$JPACKAGE" ]]; then
  echo "JDK tools not found under JAVA_HOME=$JAVA_HOME"
  exit 1
fi

MODS_DIR="$BUILD_DIR/mods"
MLIB_DIR="$BUILD_DIR/mlib"
IMAGE_DIR="$BUILD_DIR/image"
TMP_SRC="$BUILD_DIR/tmp_src"
PKG_DIR="$BUILD_DIR/installer"

rm -rf "$BUILD_DIR"
mkdir -p "$MODS_DIR" "$MLIB_DIR" "$IMAGE_DIR" "$TMP_SRC" "$PKG_DIR"

mkdir -p "$TMP_SRC/$MODULE_NAME"
cp -R "$SRC_DIR/." "$TMP_SRC/$MODULE_NAME/"

cat > "$TMP_SRC/$MODULE_NAME/module-info.java" <<EOF
module $MODULE_NAME {
    requires javafx.base;
    requires javafx.graphics;
    requires javafx.controls;
    requires javafx.fxml;

    opens com.sudo to javafx.graphics, javafx.fxml;
    exports com.sudo;
}
EOF

"$JAVAC" \
  --module-source-path "$TMP_SRC" \
  --module-path "$JAVAFX_SDK_DIR/lib" \
  -d "$MODS_DIR" \
  $(find "$TMP_SRC" -name "*.java")

"$JAR" --create --file "$MLIB_DIR/$APP_NAME.jar" -C "$MODS_DIR/$MODULE_NAME" .

"$JLINK" \
  --module-path "$MLIB_DIR:$JAVA_HOME/jmods:$JAVAFX_SDK_DIR/lib" \
  --add-modules "$MODULE_NAME,javafx.controls,javafx.fxml,javafx.graphics" \
  --output "$IMAGE_DIR" \
  --launcher "$APP_NAME=$MODULE_NAME/$MAIN_CLASS" \
  --strip-debug \
  --compress=2 \
  --no-header-files \
  --no-man-pages

JPACKAGE_ARGS=(
  --type "$PACKAGE_TYPE"
  --name "$APP_NAME"
  --app-version "$APP_VERSION"
  --input "$MLIB_DIR"
  --module "$MODULE_NAME/$MAIN_CLASS"
  --runtime-image "$IMAGE_DIR"
  --dest "$PKG_DIR"
  --vendor "$PACKAGE_VENDOR"
  --description "$PACKAGE_DESCRIPTION"
)

ICON_PATH=""
if [[ -n "$PACKAGE_ICON" && -f "$PACKAGE_ICON" ]]; then
  ICON_PATH="$PACKAGE_ICON"
elif [[ -n "$PACKAGE_ICON" && -f "$PROJECT_DIR/$PACKAGE_ICON" ]]; then
  ICON_PATH="$PROJECT_DIR/$PACKAGE_ICON"
fi

if [[ -n "$ICON_PATH" ]]; then
  JPACKAGE_ARGS+=( --icon "$ICON_PATH" )
fi

"$JPACKAGE" "${JPACKAGE_ARGS[@]}"
