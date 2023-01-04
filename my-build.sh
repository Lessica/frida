#!/bin/sh

export FRIDA_VERSION="16.0.8"
export MACOS_CERTID="-"
export IOS_CERTID="-"
# sudo killall taskgated

make clean
make core-ios-arm64
make core-ios-arm64e

rm -r build/frida-ios-universal build/*.deb
mkdir -p build/frida-ios-universal/usr/bin
mkdir -p build/frida-ios-universal/usr/lib
mkdir -p build/frida-ios-universal/usr/lib/frida

cp -rp build/frida-ios-arm64/usr/include build/frida-ios-universal/usr/include
cp -rp build/frida-ios-arm64/usr/share build/frida-ios-universal/usr/share
cp -rp build/frida-ios-arm64/usr/lib/pkgconfig build/frida-ios-universal/usr/lib/pkgconfig

cd build/frida-ios-arm64
BINARIES=$(find usr -name "*.a" -or -name "*.dylib" -or -perm +111 -and -type f)
cd -

echo "$BINARIES" | while read -r BINARY; do
  lipo -create -arch arm64 build/frida-ios-arm64/$BINARY -arch arm64e build/frida-ios-arm64e/$BINARY -output build/frida-ios-universal/$BINARY
done

releng/devkit.py frida-core ios-arm64 frida-swift/CFrida_arm64
releng/devkit.py frida-core ios-arm64e frida-swift/CFrida_arm64e
cp -p frida-swift/CFrida_arm64/frida-* frida-swift/CFrida/
lipo -create -arch arm64 frida-swift/CFrida_arm64/libfrida-core.a -arch arm64e frida-swift/CFrida_arm64e/libfrida-core.a -output frida-swift/CFrida/libfrida-core.a
rm -r frida-swift/CFrida_arm64 frida-swift/CFrida_arm64e

nm --just-symbol-name -Ug ./frida-swift/CFrida/libfrida-core.a | grep -v "/" | grep -v -e '^$' > frida-swift/CFrida/CFrida.symbols

cd frida-swift
xcodebuild
cd -

frida-core/tools/package-server-ios.sh build/frida-ios-universal "build/re.frida.server_${FRIDA_VERSION}_iphoneos-arm.deb"

exit 0