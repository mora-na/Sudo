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

JAVAFX_SDK_DIR="${JAVAFX_SDK_DIR:-}"
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

JAVAFX_LIB_DIR="${JAVAFX_LIB_DIR:-}"
if [[ -z "$JAVAFX_LIB_DIR" ]]; then
  if [[ -n "$JAVAFX_SDK_DIR" && -d "$JAVAFX_SDK_DIR" ]]; then
    JAVAFX_SDK_DIR="$(cd "$JAVAFX_SDK_DIR" && pwd)"
    if [[ -d "$JAVAFX_SDK_DIR/lib" ]]; then
      JAVAFX_LIB_DIR="$JAVAFX_SDK_DIR/lib"
    elif [[ -d "$JAVAFX_SDK_DIR/jmods" ]]; then
      JAVAFX_LIB_DIR="$JAVAFX_SDK_DIR/jmods"
    elif [[ -f "$JAVAFX_SDK_DIR/javafx.properties" ]]; then
      JAVAFX_LIB_DIR="$JAVAFX_SDK_DIR"
    else
      found="$(find "$JAVAFX_SDK_DIR" -maxdepth 4 -type f \( -name "javafx.base.jar" -o -name "javafx.base.jmod" \) -print -quit 2>/dev/null || true)"
      if [[ -n "$found" ]]; then
        JAVAFX_LIB_DIR="$(cd "$(dirname "$found")" && pwd)"
      fi
    fi
  fi

  if [[ -z "$JAVAFX_LIB_DIR" ]]; then
    if [[ -f "$JAVA_HOME/jmods/javafx.base.jmod" ]]; then
      JAVAFX_LIB_DIR="$JAVA_HOME/jmods"
      JAVAFX_SDK_DIR="${JAVAFX_SDK_DIR:-$JAVA_HOME}"
    elif [[ -f "$JAVA_HOME/lib/javafx.base.jar" ]]; then
      JAVAFX_LIB_DIR="$JAVA_HOME/lib"
      JAVAFX_SDK_DIR="${JAVAFX_SDK_DIR:-$JAVA_HOME}"
    fi
  fi
fi

if [[ -z "$JAVAFX_LIB_DIR" || ( ! -f "$JAVAFX_LIB_DIR/javafx.base.jar" && ! -f "$JAVAFX_LIB_DIR/javafx.base.jmod" ) ]]; then
  echo "JavaFX lib dir not found. JAVAFX_SDK_DIR=$JAVAFX_SDK_DIR"
  echo "Set JAVAFX_LIB_DIR to the folder containing javafx.base.jar or javafx.base.jmod."
  exit 1
fi

MODS_DIR="$BUILD_DIR/mods"
MLIB_DIR="$BUILD_DIR/mlib"
IMAGE_DIR="$BUILD_DIR/image"
TMP_SRC="$BUILD_DIR/tmp_src"
PKG_DIR="$BUILD_DIR/installer"

rm -rf "$MODS_DIR" "$MLIB_DIR" "$IMAGE_DIR" "$TMP_SRC" "$PKG_DIR"
mkdir -p "$MODS_DIR" "$MLIB_DIR" "$TMP_SRC" "$PKG_DIR"

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
  -encoding UTF-8 \
  --module-source-path "$TMP_SRC" \
  --module-path "$JAVAFX_LIB_DIR" \
  -d "$MODS_DIR" \
  $(find "$TMP_SRC" -name "*.java")

"$JAR" --create --file "$MLIB_DIR/$APP_NAME.jar" -C "$MODS_DIR/$MODULE_NAME" .

"$JLINK" \
  --module-path "$MLIB_DIR:$JAVA_HOME/jmods:$JAVAFX_LIB_DIR" \
  --add-modules "$MODULE_NAME,javafx.controls,javafx.fxml,javafx.graphics" \
  --output "$IMAGE_DIR" \
  --launcher "$APP_NAME=$MODULE_NAME/$MAIN_CLASS" \
  --strip-debug \
  --compress=2 \
  --no-header-files \
  --no-man-pages

JAVAFX_NATIVE_DIRS=()
if [[ -d "$JAVAFX_LIB_DIR" ]]; then
  JAVAFX_NATIVE_DIRS+=("$JAVAFX_LIB_DIR")
fi
if [[ -d "$JAVAFX_SDK_DIR/bin" ]]; then
  JAVAFX_NATIVE_DIRS+=("$JAVAFX_SDK_DIR/bin")
fi
if [[ -f "$JAVA_HOME/jmods/javafx.base.jmod" || -f "$JAVA_HOME/lib/javafx.base.jar" ]]; then
  JAVAFX_NATIVE_DIRS+=("$JAVA_HOME/bin")
fi

NATIVE_TARGET_DIR="$IMAGE_DIR/lib"
if [[ "${OSTYPE:-}" == "msys"* || "${OSTYPE:-}" == "cygwin"* ]]; then
  NATIVE_TARGET_DIR="$IMAGE_DIR/bin"
fi
mkdir -p "$NATIVE_TARGET_DIR"

copied_native=0
shopt -s nullglob
for dir in "${JAVAFX_NATIVE_DIRS[@]}"; do
  for f in "$dir"/*.dylib "$dir"/*.so "$dir"/*.so.* "$dir"/*.dll; do
    cp -f "$f" "$NATIVE_TARGET_DIR/"
    copied_native=1
  done
done
shopt -u nullglob

mkdir -p "$IMAGE_DIR/lib"
if [[ -f "$JAVAFX_LIB_DIR/javafx.properties" ]]; then
  cp -f "$JAVAFX_LIB_DIR/javafx.properties" "$IMAGE_DIR/lib/"
  copied_native=1
elif [[ -f "$JAVA_HOME/lib/javafx.properties" ]]; then
  cp -f "$JAVA_HOME/lib/javafx.properties" "$IMAGE_DIR/lib/"
  copied_native=1
elif [[ -n "$JAVAFX_SDK_DIR" && -f "$JAVAFX_SDK_DIR/lib/javafx.properties" ]]; then
  cp -f "$JAVAFX_SDK_DIR/lib/javafx.properties" "$IMAGE_DIR/lib/"
  copied_native=1
fi

if [[ "$copied_native" -eq 0 ]]; then
  echo "Warning: no JavaFX native libraries were copied from $JAVAFX_SDK_DIR"
fi

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
