#!/bin/bash

set -e

function usage()
{
    cat <<EOF
Usage:
$0 xtrabackup_target [installation_directory]
$0 path_to_server_tarball [installation_directory]

Prepares a server binary directory to be used by run.sh when running XtraBackup
tests.

If the argument is one of the build targets passed to build.sh
(i.e. innodb51 innodb55 innodb56 xtradb51 xtradb55) then the
appropriate Linux tarball is downloaded from a pre-defined location and
unpacked into the specified installation  directory ('./server' by default).

Otherwise the argument is assumed to be a path to a server binary tarball.
EOF
}

if [ -z "$1" ]
then
    usage
fi

arch="`uname -m`"
if [ "$arch" = "i386" ]
then
    arch="i686"
fi

if [ "$arch" = "i686" ]
then
    maria_arch_path=x86
else
    maria_arch_path=amd64
fi

case "$1" in
    innodb51)
        url="http://s3.amazonaws.com/percona.com/downloads/community"
        tarball="mysql-5.1.70-linux-$arch-glibc23.tar.gz"
        ;;

    innodb55)
        url="http://s3.amazonaws.com/percona.com/downloads/community"
        tarball="mysql-5.5.31-linux2.6-$arch.tar.gz"
        ;;

    innodb56)
        url="http://s3.amazonaws.com/percona.com/downloads/community"
        tarball="mysql-5.6.14-linux-glibc2.5-$arch.tar.gz"
        ;;

    xtradb51)
        if which lsb_release >/dev/null 2>&1 && \
           ! lsb_release -i | grep -qi centos 
        then
            # PS 5.1.69-rel14.7 tarballs are affected by LP bug #1172916
            # and thus unusable on anything but CentOS
            url="http://www.percona.com/redir/downloads/Percona-Server-5.1/Percona-Server-5.1.67-14.4/binary/linux/$arch"
            tarball="Percona-Server-5.1.67-rel14.4-511.Linux.$arch.tar.gz"

        else
            url="http://s3.amazonaws.com/percona.com/downloads/community"
            tarball="Percona-Server-5.1.69-rel14.7-572.Linux.$arch.tar.gz"
        fi
        ;;

    xtradb55)
        if which lsb_release >/dev/null 2>&1 && \
           ! lsb_release -i | grep -qi centos
        then
            # PS 5.5.31-rel30.3 tarballs are affected by LP bug #1172916
            # and thus unusable on anything but CentOS
            url="http://www.percona.com/redir/downloads/Percona-Server-5.5/Percona-Server-5.5.30-30.1/binary/linux/$arch"
            tarball="Percona-Server-5.5.30-rel30.1-465.Linux.$arch.tar.gz"
        else
            url="http://s3.amazonaws.com/percona.com/downloads/community"
            tarball="Percona-Server-5.5.31-rel30.3-520.Linux.$arch.tar.gz"
        fi
        ;;

    xtradb56)
        if which lsb_release >/dev/null 2>&1 && \
           ! lsb_release -i | grep -qi centos
        then
            # PS 5.6.11-rc60.3 tarballs are affected by LP bug #1172916
            # and thus unusable on anything but CentOS
            url="http://www.percona.com/downloads/TESTING/Percona-Server-56/Percona-Server-5.6.10-alpha60.2/release-5.6.10-60.2/318/binary/linux/$arch"
            tarball="Percona-Server-5.6.10-alpha60.2-318.Linux.$arch.tar.gz"
        else
            url="http://s3.amazonaws.com/percona.com/downloads/community"
            tarball="Percona-Server-5.6.14-rel62.0-483.Linux.$arch.tar.gz"
        fi
        ;;

    galera55)
        url="http://www.percona.com/downloads/Percona-XtraDB-Cluster/5.5.24-23.6/binary/linux/$arch"
        tarball="Percona-XtraDB-Cluster-5.5.24-23.6.342.Linux.$arch.tar.gz"
        #galera=1
        ;;

    mariadb51)
        url="http://s3.amazonaws.com/percona.com/downloads/community"
        tarball="mariadb-5.1.67-Linux-$arch.tar.gz"
        ;;

    mariadb52)
        url="http://s3.amazonaws.com/percona.com/downloads/community"
        tarball="mariadb-5.2.14-Linux-$arch.tar.gz"
        ;;

    mariadb53)
        url="http://s3.amazonaws.com/percona.com/downloads/community"
        tarball="mariadb-5.3.12-Linux-$arch.tar.gz"
        ;;

    mariadb55)
        url="http://s3.amazonaws.com/percona.com/downloads/community"
        tarball="mariadb-5.5.32-linux-$arch.tar.gz"
        ;;

    mariadb100)
        url="http://s3.amazonaws.com/percona.com/downloads/community"
        tarball="mariadb-10.0.3-linux-$arch.tar.gz"
        ;;

    *)
        if ! test -r "$1"
        then
            echo "$1 does not exist"
            exit 1
        fi
        tarball="$1"
        ;;
esac

if test -n "$2"
then
    destdir="$2"
else
    destdir="./server"
fi

if test -d "$destdir"
then
    rm -rf "$destdir"
fi
mkdir "$destdir"

if test ! $galera
then
    if test -n "$url"
    then
        echo "Downloading $tarball"
        wget -qc "$url/$tarball"
    fi

    echo "Unpacking $tarball into $destdir"
    tar zxf $tarball -C $destdir
    sourcedir="$destdir/`ls $destdir`"
    if test -n "$sourcedir"
    then
        mv $sourcedir/* $destdir
        rm -rf $sourcedir
    fi
else
    if test ! -d galerabuild
    then
        bzr init-repo galerabuild
    fi
    cd galerabuild

    rm -rf percona-xtradb-cluster
    bzr branch lp:percona-xtradb-cluster percona-xtradb-cluster
    rm -rf galera2x
    bzr branch lp:galera/2.x galera2x
    cd percona-xtradb-cluster
    cmake -DENABLE_DTRACE=0 -DWITH_WSREP:BOOL="1" -DCMAKE_INSTALL_PREFIX="../../server"

    if test -f /proc/cpuinfo
    then
        MAKE_J=`grep '^processor' /proc/cpuinfo | wc -l`
    else
        MAKE_J=4
    fi

    make -j$MAKE_J
    make install

    cd ../galera2x
    ./scripts/build.sh
    cp libgalera_smm.so ../../server/
    cd ..
fi
