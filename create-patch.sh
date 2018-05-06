#/bin/bash

set -x -e -u

OPENSSL_VERSION=1.0.2o
OPENSSL_SHA256=ec3f5c9714ba0fd45cb4e087301eb1336c317e0d20b575a125050470e8089e4d

if [ "${PYTHON_VERSION}" == "3.4" ]; then
	PYTHON_VERSION_FULL=3.4.4
	PYTHON_SOURCE_SHA256=bc93e944025816ec360712b4c42d8d5f729eaed2b26585e9bc8844f93f0c382e
	PYTHON_PKG_SHA256=a7ed0d70989db872a229a988bd7376a54858f43abbf70fa95cbecfebe8cb5544
elif [ "${PYTHON_VERSION}" == "3.5" ]; then
	PYTHON_VERSION_FULL=3.5.4
	PYTHON_SOURCE_SHA256=6ed87a8b6c758cc3299a8b433e8a9a9122054ad5bc8aad43299cff3a53d8ca44
	PYTHON_PKG_SHA256=6209c690925c0826fa767b7c9581b8ebe556160e1eac7a0dbd13500870a097a2
else
	echo "Invalid version"
	exit 1
fi
PYTHON_PREFIX=/Library/Frameworks/Python.framework/Versions/$PYTHON_VERSION
INSTALL_DIR=$PWD/build/

# Download needed resources
curl -fsSLO https://www.python.org/ftp/python/$PYTHON_VERSION_FULL/python-$PYTHON_VERSION_FULL-macosx10.6.pkg
SHA256=$(shasum -a 256 python-$PYTHON_VERSION_FULL-macosx10.6.pkg)
test "${SHA256%% *}" = "${PYTHON_PKG_SHA256}"

curl -fsSLO https://www.python.org/ftp/python/$PYTHON_VERSION_FULL/Python-$PYTHON_VERSION_FULL.tgz
SHA256=$(shasum -a 256 Python-$PYTHON_VERSION_FULL.tgz)
test "${SHA256%% *}" = "${PYTHON_SOURCE_SHA256}"

curl -fsSLO https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz
SHA256=$(shasum -a 256 openssl-$OPENSSL_VERSION.tar.gz)
test "${SHA256%% *}" = "${OPENSSL_SHA256}"

# install python
if [ "${TRAVIS:-}" == "true" ]; then
	sudo installer -pkg python-$PYTHON_VERSION_FULL-macosx10.6.pkg -target /
fi

# let's build OpenSSL
tar -xf openssl-$OPENSSL_VERSION.tar.gz
pushd openssl-$OPENSSL_VERSION
	OPENSSL_CONF="no-krb5 no-idea no-mdc2 no-rc5 no-zlib enable-tlsext no-ssl2 no-ssl3 shared --prefix=$PYTHON_PREFIX --openssldir=$PYTHON_PREFIX/etc/openssl"
	./Configure darwin-i386-cc --install_prefix=$INSTALL_DIR/i386 $OPENSSL_CONF &> /dev/null
	make depend &>/dev/null
	make all &>/dev/null
	make install_sw &>/dev/null
	make clean &>/dev/null

	./Configure darwin64-x86_64-cc enable-ec_nistp_64_gcc_128 --install_prefix=$INSTALL_DIR/x86_64 $OPENSSL_CONF &> /dev/null
	make depend &>/dev/null
	make all &>/dev/null
	make install_sw &>/dev/null
	make clean &>/dev/null

	mkdir -p $INSTALL_DIR/$PYTHON_PREFIX/lib
	lipo -create $INSTALL_DIR/i386/$PYTHON_PREFIX/lib/libcrypto.1.0.0.dylib $INSTALL_DIR/x86_64/$PYTHON_PREFIX/lib/libcrypto.1.0.0.dylib -output $INSTALL_DIR/$PYTHON_PREFIX/lib/libcrypto.1.0.0.dylib
	lipo -create $INSTALL_DIR/i386/$PYTHON_PREFIX/lib/libssl.1.0.0.dylib $INSTALL_DIR/x86_64/$PYTHON_PREFIX/lib/libssl.1.0.0.dylib -output $INSTALL_DIR/$PYTHON_PREFIX/lib/libssl.1.0.0.dylib
	pushd $INSTALL_DIR/$PYTHON_PREFIX/lib
		ln -s libcrypto.1.0.0.dylib libcrypto.dylib
		ln -s libssl.1.0.0.dylib libssl.dylib
	popd
popd

# copy OpenSSL in final dir
sudo chown root:admin $INSTALL_DIR/$PYTHON_PREFIX/lib/lib*.dylib
sudo cp -rf $INSTALL_DIR/$PYTHON_PREFIX/lib/lib*.dylib $PYTHON_PREFIX/lib/

# build _ssl module
tar -xf Python-$PYTHON_VERSION_FULL.tgz
pushd Python-$PYTHON_VERSION_FULL/Modules
	# create files needed by setup.py
	mkdir Modules
	touch Modules/Setup
	touch Modules/Setup.local
	# patch setup.py
	sed -i.bak "s/not in disabled_module_list/== '_ssl'/g" ../setup.py
	# build _ssl module
	LDFLAGS="-L$INSTALL_DIR/$PYTHON_PREFIX/lib" CFLAGS="-arch i386 -arch x86_64 -I$INSTALL_DIR/x86_64/$PYTHON_PREFIX/include" $PYTHON_PREFIX/bin/python3 ../setup.py build_ext -I $INSTALL_DIR/x86_64/$PYTHON_PREFIX/include -L $INSTALL_DIR/$PYTHON_PREFIX/lib
	# move _ssl module at the right place
	mkdir -p $INSTALL_DIR/$PYTHON_PREFIX/lib/python$PYTHON_VERSION/lib-dynload
	mv build/lib.macosx*$PYTHON_VERSION/_ssl*.so $INSTALL_DIR/$PYTHON_PREFIX/lib/python$PYTHON_VERSION/lib-dynload/
popd

# create patch
PATCH_SUFFIX=$(git describe --dirty 2>/dev/null || echo "local")
PATCH_NAME=patch-macos-python-$PYTHON_VERSION-openssl-$PATCH_SUFFIX.tar.gz
pushd $INSTALL_DIR/$PYTHON_PREFIX
	# update rights
	sudo chown -R root:admin lib
	# create tar
	tar -czf $INSTALL_DIR/../$PATCH_NAME lib
popd

# apply patch
sudo tar -C $PYTHON_PREFIX -xmf $PATCH_NAME

# test patch
OPENSSL_VERSION=$($INSTALL_DIR/x86_64$PYTHON_PREFIX/bin/openssl version 2>/dev/null)
PY64_OPENSSL_VERSION=$($PYTHON_PREFIX/bin/python$PYTHON_VERSION -c "import ssl; print(ssl.OPENSSL_VERSION)")
PY32_OPENSSL_VERSION=$($PYTHON_PREFIX/bin/python$PYTHON_VERSION-32 -c "import ssl; print(ssl.OPENSSL_VERSION)")
test "$OPENSSL_VERSION" = "$PY64_OPENSSL_VERSION"
test "$OPENSSL_VERSION" = "$PY32_OPENSSL_VERSION"
