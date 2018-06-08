#!/bin/sh

#
# Near-automatic releases.
#


if [ -z "$1" ]
  then
	echo "Usage: release.sh [version] [release]"
	exit 1
  fi

if [ -z "$2" ]
  then
	echo "Usage: release.sh [version] [release]"
	exit 1
  fi
  
VERSION=$1
RELEASE=$2

PROJECT="perihelion"


echo "======"
echo "Export Without SVN"
echo "======"

rm -rf /tmp/$PROJECT-release
mkdir /tmp/$PROJECT-release
cd /tmp/$PROJECT-release

svn export svn+ssh://aaron@svn.zadzmo.org/home/aaron/repos/$PROJECT/head \
	./$PROJECT-$VERSION 	|| exit 1

cd $PROJECT-$VERSION


echo "======"
echo "Running tests"
echo "======"

cd tests/
lua5.1 tests.lua || exit 1  
lua5.2 tests.lua || exit 1
lua5.3 tests.lua || exit 1
cd ../

echo "======"
echo "Check Version Number"
echo "======"

v1=`lua ./printver.lua`
v2="$VERSION `date +%Y.%m%d`"

echo $v1
echo $v2

if [ "$v1" != "$v2" ]
  then
	echo "Version number not right!"
	exit 1
  fi


#echo "======"
#echo "Generate Docs"
#echo "======"

#ldoc . || exit 1


echo "======"
echo "Rockspec handling"
echo "======"

sed -ie "s/%VERSION%/$VERSION/g" $PROJECT.rockspec 	|| exit 1
sed -ie "s/%RELEASE%/$RELEASE/g" $PROJECT.rockspec	|| exit 1


echo "======"
echo "Tarball"
echo "======"

cd ..
tar -cvf $PROJECT-$VERSION.tar $PROJECT-$VERSION
gzip -9 $PROJECT-$VERSION.tar

cp $PROJECT-$VERSION/$PROJECT.rockspec $PROJECT-$VERSION-$RELEASE.rockspec
