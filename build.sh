# INSTALL xcpretty: sudo gem install xcpretty

SCHEME='MTMR'
APP_NAME='MTMR tovam'

rm -r Release 2>/dev/null

xcodebuild archive \
	-scheme "$SCHEME" \
	-archivePath Release/App.xcarchive | xcpretty -c

xcodebuild \
	-exportArchive \
	-archivePath Release/App.xcarchive \
	-exportOptionsPlist export-options.plist \
	-exportPath Release | xcpretty -c

cd Release
rm -r App.xcarchive

# Prerequisite: npm i -g create-dmg
APP_BUNDLE="${APP_NAME}.app"
echo $APP_BUNDLE
create-dmg "$APP_BUNDLE"

DATE=`LC_ALL=en_US.utf8 date +"%a, %d %b %Y %H:%M:%S %z"`
BUILD=`/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${APP_BUNDLE}/Contents/Info.plist"`
VERSION=`/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP_BUNDLE}/Contents/Info.plist"`
MINIMUM=`/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "${APP_BUNDLE}/Contents/Info.plist"`
DMG_NAME="${APP_NAME} ${VERSION}.dmg"
DMG_URL_NAME=`printf "%s" "$DMG_NAME" | sed 's/ /%20/g'`
SIZE=`stat -f%z "$DMG_NAME"`
SIGN=`~/Sparkle/bin/sign_update "$DMG_NAME" ~/Sparkle/bin/dsa_priv.pem | awk '{printf "%s",$0} END {print ""}'`
SHA256=`shasum -a 256 "$DMG_NAME" | awk '{print $1}'`

# ditto -c -k --sequesterRsrc --keepParent "${NAME}.app" "${NAME}v${VERSION}.zip"

echo DATE $DATE
echo VERSION $VERSION
echo BUILD $BUILD
echo MINIMUM $MINIMUM
echo SIZE $SIZE
echo SIGN ${SIGN}

echo "<?xml version=\"1.0\" standalone=\"yes\"?>
<rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\" version=\"2.0\">
    <channel>
		<item>
			<title>${VERSION}</title>
			<pubDate>${DATE}</pubDate>
			<description>
				${1}
			</description>
			<sparkle:minimumSystemVersion>${MINIMUM}</sparkle:minimumSystemVersion>
			<enclosure url=\"https://mtmr.app/${DMG_URL_NAME}\"
				sparkle:version=\"${BUILD}\"
				sparkle:shortVersionString=\"${VERSION}\"
				length=\"${SIZE}\"
				type=\"application/octet-stream\"
				sparkle:dsaSignature=\"${SIGN}\"
			/>
		</item>
	</channel>
</rss>" > appcast.xml

echo ""
echo "Homebrew   https://github.com/Homebrew/homebrew-cask/edit/master/Casks/mtmr.rb"
echo ""
echo "  version \"${VERSION}\""
echo "  sha256 \"${SHA256}\""
echo ""
echo "Update MTMR v${VERSION}"

scp "$DMG_NAME" do:/var/www/mtmr
scp appcast.xml do:/var/www/mtmr
