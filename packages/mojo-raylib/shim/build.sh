#!/usr/bin/env bash
# Pixi owns the source/flags/compiler cache; do not reuse an external native build.
set -euo pipefail

if [ ! -f vendor/raylib/src/raylib.h ]; then
  echo 'raylib submodule missing: run git submodule update --init' >&2
  exit 1
fi

export CC=clang CXX=clang++
if [ "$(uname -s)" = Darwin ]; then
  # Match the other native packages: Conda Clang's LTO driver cannot link with Xcode.
  export CC=/usr/bin/clang CXX=/usr/bin/clang++
fi
cmake -S vendor/raylib -B build-raylib \
  ${CMAKE_ARGS:-} \
  -G Ninja \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_PREFIX_PATH="$PREFIX" \
  -DCMAKE_C_FLAGS_RELEASE="-O3 -march=native -DNDEBUG" \
  -DCMAKE_CXX_FLAGS_RELEASE="-O3 -march=native -DNDEBUG" \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DBUILD_SHARED_LIBS=ON \
  -DBUILD_EXAMPLES=OFF \
  -DBUILD_GAMES=OFF \
  -DGLFW_BUILD_X11=ON \
  -DGLFW_BUILD_WAYLAND=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_LIBDIR=lib
cmake --build build-raylib
cmake --install build-raylib --prefix "$PREFIX"

case "$(uname -s)" in
  Darwin)
    "$CC" -O3 -march=native -dynamiclib -fPIC \
      -I vendor/raylib/src native/mojo_raylib_shim.c \
      -L"$PREFIX/lib" -lraylib \
      -Wl,-install_name,@rpath/libmojo_raylib_shim.dylib \
      -o "$PREFIX/lib/libmojo_raylib_shim.dylib"
    ;;
  Linux)
    "$CC" -O3 -march=native -shared -fPIC \
      -I vendor/raylib/src native/mojo_raylib_shim.c \
      -L"$PREFIX/lib" -lraylib \
      -Wl,-rpath,'$ORIGIN' \
      -o "$PREFIX/lib/libmojo_raylib_shim.so"
    ;;
  *) echo "Unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac
