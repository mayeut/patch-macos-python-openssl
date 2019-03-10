patch-macos-python-openssl [![badge-build]][link-build]
=======================================================
Create _ssl module patch with updated OpenSSL for macOS Python 3.4.4 & 3.5.4 **official installers**

Why a patch ?
-------------
macOS python 3.4.4 & 3.5.4 official installers are using Apple provided OpenSSL 0.9.8 which does not support TLS v1.1/v1.2

What is the patch ?
-------------------
The patch provides OpenSSL 1.0.2r and an _ssl module rebuilt using this updated OpenSSL

How to install the patch ?
--------------------------
For Python 3.4.4:
```
curl -fsSLO https://github.com/mayeut/patch-macos-python-openssl/releases/download/v1.0.2r/patch-macos-python-3.4-openssl-v1.0.2r.tar.gz
sudo tar -C /Library/Frameworks/Python.framework/Versions/3.4/ -xmf patch-macos-python-3.4-openssl-v1.0.2r.tar.gz
```
For Python 3.5.4:
```
curl -fsSLO https://github.com/mayeut/patch-macos-python-openssl/releases/download/v1.0.2r/patch-macos-python-3.5-openssl-v1.0.2r.tar.gz
sudo tar -C /Library/Frameworks/Python.framework/Versions/3.5/ -xmf patch-macos-python-3.5-openssl-v1.0.2r.tar.gz
```

[badge-build]: https://travis-ci.org/mayeut/patch-macos-python-openssl.svg?branch=master "Build Status"
[link-build]: https://travis-ci.org/mayeut/patch-macos-python-openssl "Build Status"
