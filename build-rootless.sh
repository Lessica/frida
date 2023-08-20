#!/bin/sh

export FRIDA_VERSION="16.1.3"
export MACOS_CERTID="-"
export IOS_CERTID="-"
# sudo killall taskgated

# make clean
make core-ios-arm64
make core-ios-arm64e

rm -r build/frida-ios-universal build/*.deb

JB_PREFIX=""
FRIDA_ARCH="iphoneos-arm"
if [ "$ROOTLESS" = "1" ]; then
JB_PREFIX="/var/jb"
FRIDA_ARCH="iphoneos-arm64"
fi

mkdir -p build/frida-ios-universal$JB_PREFIX/usr/bin
mkdir -p build/frida-ios-universal$JB_PREFIX/usr/lib
mkdir -p build/frida-ios-universal$JB_PREFIX/usr/lib/frida
cp -rp build/frida-ios-arm64/usr/include build/frida-ios-universal$JB_PREFIX/usr/include
cp -rp build/frida-ios-arm64/usr/share build/frida-ios-universal$JB_PREFIX/usr/share
cp -rp build/frida-ios-arm64/usr/lib/pkgconfig build/frida-ios-universal$JB_PREFIX/usr/lib/pkgconfig

cd build/frida-ios-arm64
BINARIES=$(find usr -name "*.a" -or -name "*.dylib" -or -perm +111 -and -type f)
cd -

echo "$BINARIES" | while read -r BINARY; do
  lipo -create -arch arm64 build/frida-ios-arm64/$BINARY -arch arm64e build/frida-ios-arm64e/$BINARY -output build/frida-ios-universal$JB_PREFIX/$BINARY
done

releng/devkit.py frida-core ios-arm64 frida-swift/CFrida_arm64
releng/devkit.py frida-core ios-arm64e frida-swift/CFrida_arm64e
cp -p frida-swift/CFrida_arm64/frida-* frida-swift/CFrida/
lipo -create -arch arm64 frida-swift/CFrida_arm64/libfrida-core.a -arch arm64e frida-swift/CFrida_arm64e/libfrida-core.a -output frida-swift/CFrida/libfrida-core.a
rm -r frida-swift/CFrida_arm64 frida-swift/CFrida_arm64e

nm --just-symbol-name -Ug ./frida-swift/CFrida/libfrida-core.a | grep -v "/" | grep -v -e '^$' > frida-swift/CFrida/CFrida.symbols

cd frida-swift
xcodebuild clean
xcodebuild
cd -

mkdir -p build/frida-ios-universal$JB_PREFIX/Library/Frameworks
cp -rp frida-swift/build/Release-iphoneos/Frida.framework build/frida-ios-universal$JB_PREFIX/Library/Frameworks/Frida.framework

TMPDIR="$(mktemp -d /tmp/package-server.XXXXXX)"
mkdir -p $TMPDIR$JB_PREFIX/usr/sbin
cp build/frida-ios-universal$JB_PREFIX/usr/bin/frida-server $TMPDIR$JB_PREFIX/usr/sbin/frida-server
chmod 755 $TMPDIR$JB_PREFIX/usr/sbin/frida-server

mkdir -p $TMPDIR$JB_PREFIX/usr/lib/frida
cp build/frida-ios-universal$JB_PREFIX/usr/lib/frida/frida-agent.dylib $TMPDIR$JB_PREFIX/usr/lib/frida/frida-agent.dylib
chmod 755 $TMPDIR$JB_PREFIX/usr/lib/frida/frida-agent.dylib

mkdir -p $TMPDIR$JB_PREFIX/Library/Frameworks
cp -r build/frida-ios-universal$JB_PREFIX/Library/Frameworks/Frida.framework $TMPDIR$JB_PREFIX/Library/Frameworks/Frida.framework
ldid -S $TMPDIR$JB_PREFIX/Library/Frameworks/Frida.framework/Frida

mkdir -p $TMPDIR$JB_PREFIX/Library/LaunchDaemons
cat > $TMPDIR$JB_PREFIX/Library/LaunchDaemons/re.frida.server.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>re.frida.server</string>
	<key>ProgramArguments</key>
	<array>
		<string>$JB_PREFIX/usr/sbin/frida-server</string>
	</array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>CRYPTEX_MOUNT_PATH</key>
        <string>$JB_PREFIX</string>
    </dict>
	<key>UserName</key>
	<string>root</string>
	<key>GroupName</key>
	<string>wheel</string>
	<key>HighPriorityIO</key>
	<true/>
	<key>EnablePressuredExit</key>
	<false/>
	<key>EnableTransactions</key>
	<false/>
	<key>POSIXSpawnType</key>
	<string>Interactive</string>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ThrottleInterval</key>
	<integer>5</integer>
	<key>ExecuteAllowed</key>
	<true/>
	<key>_AdditionalProperties</key>
	<dict>
		<key>RunningBoard</key>
		<dict>
			<key>Managed</key>
			<false/>
			<key>Reported</key>
			<false/>
		</dict>
	</dict>
</dict>
</plist>
EOF
chmod 644 $TMPDIR$JB_PREFIX/Library/LaunchDaemons/re.frida.server.plist

INSTALLED_SIZE=$(du -sk "$TMPDIR" | cut -f1)

mkdir -p $TMPDIR/DEBIAN
cat > $TMPDIR/DEBIAN/control <<EOF
Package: re.frida.server
Name: Frida
Version: $FRIDA_VERSION
Priority: optional
Size: 1337
Installed-Size: $INSTALLED_SIZE
Architecture: $FRIDA_ARCH
Description: Observe and reprogram running programs.
Homepage: https://frida.re/
Maintainer: Ole André Vadla Ravnås <oleavr@nowsecure.com>
Author: Frida Developers <oleavr@nowsecure.com>
Section: Development
Conflicts: re.frida.server64
EOF
chmod 644 $TMPDIR/DEBIAN/control

cat > $TMPDIR/DEBIAN/extrainst_ <<EOF
#!/bin/sh

JB_PREFIX=""
if [ -e /var/jb ]; then
  JB_PREFIX="/var/jb"
fi

if [ "\$1" = upgrade ]; then
  launchctl unload -w "\$JB_PREFIX/Library/LaunchDaemons/re.frida.server.plist"
fi

sleep 2

if [ "\$1" = install ] || [ "\$1" = upgrade ]; then
  launchctl load -w "\$JB_PREFIX/Library/LaunchDaemons/re.frida.server.plist"
fi

exit 0
EOF
chmod 755 $TMPDIR/DEBIAN/extrainst_

cat > $TMPDIR/DEBIAN/prerm <<EOF
#!/bin/sh

if [ "\$1" = remove ] || [ "\$1" = purge ]; then
  launchctl unload -w "\$JB_PREFIX/Library/LaunchDaemons/re.frida.server.plist"
fi

exit 0
EOF
chmod 755 $TMPDIR/DEBIAN/prerm

mkdir -p packages
OUTPUT_DEB="packages/re.frida.server_${FRIDA_VERSION}_${FRIDA_ARCH}.deb"

dpkg-deb -Zxz --root-owner-group --build $TMPDIR $OUTPUT_DEB
PACKAGE_SIZE=$(expr $(du -sk $OUTPUT_DEB | cut -f1) \* 1024)

sed \
  -e "s,^Size: 1337$,Size: $PACKAGE_SIZE,g" \
  $TMPDIR/DEBIAN/control > $TMPDIR/DEBIAN/control_
mv $TMPDIR/DEBIAN/control_ $TMPDIR/DEBIAN/control
dpkg-deb -Zxz --root-owner-group --build $TMPDIR $OUTPUT_DEB

rm -rf $TMPDIR

exit 0