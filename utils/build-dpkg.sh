#!/bin/bash
# Usage: build-dpkg.sh [target dir]
# The default target directory is the current directory. If it is not
# supplied and the current directory is not empty, it will issue an error in
# order to avoid polluting the current directory after a test run.
#
# The program will setup the dpkg building environment and ultimately call
# dpkg-buildpackage with the appropiate parameters.
#

# Bail out on errors, be strict
set -ue

# Examine parameters
go_out="$(getopt --options "k:KbBSnTtD" --longoptions \
    key:,nosign,binary,binarydep,source,dummy,notransitional,transitional \
    --name "$(basename "$0")" -- "$@")"
test $? -eq 0 || exit 1
eval set -- $go_out

BUILDPKG_KEY=''
DPKG_BINSRC=''
DUMMY=''
NOTRANSITIONAL='yes'
PACKAGE_SUFFIX='-1'

for arg
do
    case "$arg" in
    -- ) shift; break;;
    -k | --key ) shift; BUILDPKG_KEY="-pgpg -k$1"; shift;;
    -K | --nosign ) shift; BUILDPKG_KEY="-uc -us";;
    -b | --binary ) shift; DPKG_BINSRC='-b';;
    -B | --binarydep ) shift; DPKG_BINSRC='-B';;
    -S | --source ) shift; DPKG_BINSRC='-S';;
    -n | --dummy ) shift; DUMMY='yes';;
    -T | --notransitional ) shift; NOTRANSITIONAL='yes';;
    -t | --transitional ) shift; NOTRANSITIONAL='';;
    -D ) shift; PACKAGE_SUFFIX="$PACKAGE_SUFFIX.$(lsb_release -sc)";;
    esac
done

SOURCEDIR="$(cd $(dirname "$0"); cd ..; pwd)"

# Read XTRABACKUP_VERSION from the VERSION file
. $SOURCEDIR/VERSION

DEBIAN_VERSION="$(lsb_release -sc)"
REVISION="$(cd "$SOURCEDIR"; bzr revno 2>/dev/null || cat REVNO)"
FULL_VERSION="$XTRABACKUP_VERSION-$REVISION.$DEBIAN_VERSION"

# Working directory
if test "$#" -eq 0
then
    # We build in the sourcedir
    WORKDIR="$(cd "$SOURCEDIR/.."; pwd)"

elif test "$#" -eq 1
then
    WORKDIR="$1"

    # Check that the provided directory exists and is a directory
    if ! test -d "$WORKDIR"
    then
        echo >&2 "$WORKDIR is not a directory"
        exit 1
    fi

else
    echo >&2 "Usage: $0 [target dir]"
    exit 1

fi

# Build information
export CC=${CC:-gcc}
export CXX=${CXX:-g++}
export CFLAGS="-fPIC -Wall -O3 -g -static-libgcc -fno-omit-frame-pointer"
export CXXFLAGS="-O2 -fno-omit-frame-pointer -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2"
export MAKE_JFLAG=-j4

export DEB_BUILD_OPTIONS='debug nocheck'
export DEB_CFLAGS_APPEND="$CFLAGS -DXTRABACKUP_REVISION=\\\"$REVISION\\\""
export DEB_CXXFLAGS_APPEND="$CXXFLAGS -DXTRABACKUP_REVISION=\\\"$REVISION\\\""
export DEB_DUMMY="$DUMMY"

# Build
(
    (
        # Prepare source directory for dpkg-source
        cd "$SOURCEDIR"

        make DUMMY="$DUMMY" dist

        if ! test -d debian
        then
            cp -a utils/debian/ .
        fi

        # Update distribution
        dch -m -D "$DEBIAN_VERSION" --force-distribution \
            -v "$XTRABACKUP_VERSION-$REVISION$PACKAGE_SUFFIX" 'Update distribution'

    )

    # Create the original tarball
    mv "$SOURCEDIR/percona-xtrabackup-$XTRABACKUP_VERSION-$REVISION.tar.gz" \
        "$WORKDIR/percona-xtrabackup_$XTRABACKUP_VERSION-$REVISION.orig.tar.gz"

    (
        cd "$WORKDIR"

        # Create the rest of the source, ignoring changes since we may be in the
        # sourcedir.
        dpkg-source -i'.*' -b "$SOURCEDIR"

        # Unpack it
        dpkg-source -x "percona-xtrabackup_$XTRABACKUP_VERSION-$REVISION$PACKAGE_SUFFIX.dsc"

        (
            cd "percona-xtrabackup-$XTRABACKUP_VERSION-$REVISION"

            # Don't build transitional packages if requested
            if test "x$NOTRANSITIONAL" = "xyes"
            then
                sed -i '/Package: xtrabackup/,/^$/d' debian/control
            fi

            # Issue dpkg-buildpackage command
            dpkg-buildpackage $DPKG_BINSRC $BUILDPKG_KEY
 
        )

        rm -rf "percona-xtrabackup-$XTRABACKUP_VERSION-$REVISION"
 
    )
)
