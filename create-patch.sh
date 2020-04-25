#/bin/bash

set -x -e -u

OPENSSL_VERSION=1.1.1h
OPENSSL_SHA256=5c9ca8774bd7b03e5784f26ae9e9e6d749c9da2438545077e6b3d755a06595d9

if [ "${PYTHON_VERSION}" == "3.5" ]; then
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
	sudo patch -u -i $(pwd)/test_ssl.py.patch -d ${PYTHON_PREFIX}/lib/python${PYTHON_VERSION}/test
	sudo curl -fsSLo ${PYTHON_PREFIX}/lib/python${PYTHON_VERSION}/test/keycert.pem https://raw.githubusercontent.com/python/cpython/v3.5.10/Lib/test/keycert.pem
	sudo curl -fsSLo ${PYTHON_PREFIX}/lib/python${PYTHON_VERSION}/test/ffdh3072.pem https://raw.githubusercontent.com/python/cpython/v3.5.10/Lib/test/ffdh3072.pem
fi

# install certifi
curl -fsSL https://bootstrap.pypa.io/get-pip.py | $PYTHON_PREFIX/bin/python$PYTHON_VERSION
$PYTHON_PREFIX/bin/python$PYTHON_VERSION -m pip install -U certifi

# let's build OpenSSL
tar -xf openssl-$OPENSSL_VERSION.tar.gz
pushd openssl-$OPENSSL_VERSION
	OPENSSL_CONF="no-idea no-mdc2 no-rc5 no-zlib no-ssl2 no-ssl3 shared --prefix=$PYTHON_PREFIX --openssldir=$PYTHON_PREFIX/etc/openssl"
	./Configure darwin-i386-cc $OPENSSL_CONF &> /dev/null
	make depend &>/dev/null
	make all &>/dev/null
	make test &> /dev/null
	make DESTDIR=$INSTALL_DIR/i386 install_sw &>/dev/null
	make clean &>/dev/null

	./Configure darwin64-x86_64-cc enable-ec_nistp_64_gcc_128 $OPENSSL_CONF &> /dev/null
	make depend &>/dev/null
	make all &>/dev/null
	make test &> /dev/null
	make DESTDIR=$INSTALL_DIR/x86_64 install_sw &>/dev/null
	make clean &>/dev/null

	mkdir -p $INSTALL_DIR/$PYTHON_PREFIX/lib
	lipo -create $INSTALL_DIR/i386/$PYTHON_PREFIX/lib/libcrypto.1.1.dylib $INSTALL_DIR/x86_64/$PYTHON_PREFIX/lib/libcrypto.1.1.dylib -output $INSTALL_DIR/$PYTHON_PREFIX/lib/libcrypto.1.1.dylib
	lipo -create $INSTALL_DIR/i386/$PYTHON_PREFIX/lib/libssl.1.1.dylib $INSTALL_DIR/x86_64/$PYTHON_PREFIX/lib/libssl.1.1.dylib -output $INSTALL_DIR/$PYTHON_PREFIX/lib/libssl.1.1.dylib
	pushd $INSTALL_DIR/$PYTHON_PREFIX/lib
		ln -s libcrypto.1.1.dylib libcrypto.dylib
		ln -s libssl.1.1.dylib libssl.dylib
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
	# copy certificates
	mkdir -p etc/openssl
	cp -f $($PYTHON_PREFIX/bin/python$PYTHON_VERSION -m certifi) etc/openssl/cert.pem
	# update rights
	sudo chown -R root:admin lib etc
	# create tar
	tar -czf $INSTALL_DIR/../$PATCH_NAME lib etc
popd

# apply patch
sudo tar -C $PYTHON_PREFIX -xmf $PATCH_NAME

# test patch
OPENSSL_VERSION=$($INSTALL_DIR/x86_64$PYTHON_PREFIX/bin/openssl version 2>/dev/null)
PY64_OPENSSL_VERSION=$($PYTHON_PREFIX/bin/python$PYTHON_VERSION -c "import ssl; print(ssl.OPENSSL_VERSION)")
PY32_OPENSSL_VERSION=$($PYTHON_PREFIX/bin/python$PYTHON_VERSION-32 -c "import ssl; print(ssl.OPENSSL_VERSION)")
test "$OPENSSL_VERSION" = "$PY64_OPENSSL_VERSION"
test "$OPENSSL_VERSION" = "$PY32_OPENSSL_VERSION"
$PYTHON_PREFIX/bin/python$PYTHON_VERSION -m test -vvv test_ssl
$PYTHON_PREFIX/bin/python$PYTHON_VERSION-32 -m test -vvv test_ssl
$PYTHON_PREFIX/bin/python$PYTHON_VERSION -c "from urllib.request import urlopen; print(urlopen('https://raw.githubusercontent.com/mayeut/patch-macos-python-openssl/master/README.md').read())"
$PYTHON_PREFIX/bin/python$PYTHON_VERSION-32 -c "from urllib.request import urlopen; print(urlopen('https://raw.githubusercontent.com/mayeut/patch-macos-python-openssl/master/README.md').read())"
