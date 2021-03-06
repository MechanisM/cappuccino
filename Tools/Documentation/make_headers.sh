#!/bin/sh
#
# NOTE: The working directory should be the main capp directory when this script is run

if [ -d AppKit.doc ]; then
    rm -rf AppKit.doc
fi

if [ -d Foundation.doc ]; then
    rm -rf Foundation.doc
fi

echo "Processing source files..."
tar cf AppKit.doc.tar --exclude='_*' -s /^AppKit/AppKit.doc/ AppKit/*.j AppKit/**/*.j
tar xf AppKit.doc.tar
rm AppKit.doc.tar

tar cf Foundation.doc.tar --exclude='_*' -s /^Foundation/Foundation.doc/ Foundation/*.j Foundation/**/*.j
tar xf Foundation.doc.tar
rm Foundation.doc.tar

find AppKit.doc -name *.j -exec sed -e '/@import.*/ d' -i '' {} \;
find Foundation.doc -name *.j -exec sed -e '/@import.*/ d' -i '' {} \;

exec Tools/Documentation/make_headers
