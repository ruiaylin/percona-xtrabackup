set -eu

function innobackupex()
{
    run_cmd $IB_BIN $IB_ARGS $*
}

function xtrabackup()
{
    run_cmd $XB_BIN $XB_ARGS $*
}

function vlog
{
    echo "`date +"%F %T"`: `basename "$0"`: $@" >&2
}


function clean()
{
    rm -rf ${TEST_BASEDIR}/var[0-9]
}

function die()
{
  vlog "$*" >&2
  exit 1
}

function call_mysql_install_db()
{
	vlog "Calling mysql_install_db"
	cd $MYSQL_BASEDIR
	$MYSQL_INSTALL_DB --defaults-file=${MYSQLD_VARDIR}/my.cnf \
                    --basedir=${MYSQL_BASEDIR} \
                    ${MYSQLD_EXTRA_ARGS}
	cd -
}

########################################################################
# Checks whether MySQL is alive
########################################################################
function mysql_ping()
{
    $MYSQLADMIN $MYSQL_ARGS --wait=100 ping >/dev/null 2>&1 || return 1
}

function kill_leftovers()
{
    local file
    for file in ${TEST_BASEDIR}/mysqld*.pid
    do
	if [ -f $file ]
	then
	    vlog "Found a leftover mysqld processes with PID `cat $file`, stopping it"
	    kill -9 `cat $file` 2>/dev/null || true
	    rm -f $file
	fi
    done
}

function run_cmd()
{
  vlog "===> $@"
  set +e
  "$@"
  local rc=$?
  set -e
  if [ $rc -ne 0 ]
  then
      die "===> `basename $1` failed with exit code $rc"
  fi
}

function run_cmd_expect_failure()
{
  vlog "===> $@"
  set +e
  "$@"
  local rc=$?
  set -e
  if [ $rc -eq 0 ]
  then
      die "===> `basename $1` succeeded when it was expected to fail"
  fi
}

function load_sakila()
{
vlog "Loading sakila"
${MYSQL} ${MYSQL_ARGS} -e "create database sakila"
vlog "Loading sakila scheme"
${MYSQL} ${MYSQL_ARGS} sakila < inc/sakila-db/sakila-schema.sql
vlog "Loading sakila data"
${MYSQL} ${MYSQL_ARGS} sakila < inc/sakila-db/sakila-data.sql
}

function load_dbase_schema()
{
vlog "Loading $1 database schema"
${MYSQL} ${MYSQL_ARGS} -e "create database $1"
${MYSQL} ${MYSQL_ARGS} $1 < inc/$1-db/$1-schema.sql
}

function load_dbase_data()
{
vlog "Loading $1 database data"
${MYSQL} ${MYSQL_ARGS} $1 < inc/$1-db/$1-data.sql
}

function drop_dbase()
{
  vlog "Dropping database $1"
  run_cmd ${MYSQL} ${MYSQL_ARGS} -e "DROP DATABASE $1"
}

########################################################################
# Choose a free port for a MySQL server instance
########################################################################
function get_free_port()
{
    local id=$1
    local port
    local lockfile

    for (( port=PORT_BASE+id; port < 65535; port++))
    do
	lockfile="/tmp/xtrabackup_port_lock.$port"
	# Try to atomically lock the current port number
	if ! set -C > $lockfile
	then
	    set +C
	    # check if the process still exists
	    if kill -0 "`cat $lockfile`"
	    then
		continue;
	    fi
	    # stale file, overwrite it with the current PID
	fi
	set +C
	echo $$ > $lockfile
	if ! nc -z -w1 localhost $port >/dev/null 2>&1
	then
	    echo $port
	    return 0
	fi
	rm -f $lockfile
    done

    die "Could not find a free port for server id $id!"
}

function free_reserved_port()
{
   local port=$1

   rm -f /tmp/xtrabackup_port_lock.${port}
}


########################################################################
# Initialize server variables such as datadir, tmpdir, etc. and store
# them with the specified index in SRV_MYSQLD_* arrays to be used by
# switch_server() later
########################################################################
function init_server_variables()
{
    local id=$1

    if [ -n ${SRV_MYSQLD_IDS[$id]:-""} ]
    then
	die "Server with id $id has already been started"
    fi

    SRV_MYSQLD_IDS[$id]="$id"
    local vardir="${TEST_BASEDIR}/var${id}"
    SRV_MYSQLD_VARDIR[$id]="$vardir"
    SRV_MYSQLD_DATADIR[$id]="$vardir/data"
    SRV_MYSQLD_TMPDIR[$id]="$vardir/tmp"
    SRV_MYSQLD_PIDFILE[$id]="${TEST_BASEDIR}/mysqld${id}.pid"
    SRV_MYSQLD_ERRFILE[$id]="$vardir/data/mysqld${id}.err"
    SRV_MYSQLD_PORT[$id]=`get_free_port $id`
    SRV_MYSQLD_SOCKET[$id]=`mktemp -t xtrabackup.mysql.sock.XXXXXX`
}

########################################################################
# Reset server variables
########################################################################
function reset_server_variables()
{
    local id=$1

    if [ -z ${SRV_MYSQLD_VARDIR[$id]:-""} ]
    then
	# Variables have already been reset
	return 0;
    fi

    SRV_MYSQLD_IDS[$id]=
    SRV_MYSQLD_VARDIR[$id]=
    SRV_MYSQLD_DATADIR[$id]=
    SRV_MYSQLD_TMPDIR[$id]=
    SRV_MYSQLD_PIDFILE[$id]=
    SRV_MYSQLD_ERRFILE[$id]=
    SRV_MYSQLD_PORT[$id]=
    SRV_MYSQLD_SOCKET[$id]=
}

##########################################################################
# Change the environment to make all utilities access the server with an
# id specified in the argument.
##########################################################################
function switch_server()
{
    local id=$1

    MYSQLD_VARDIR="${SRV_MYSQLD_VARDIR[$id]}"
    MYSQLD_DATADIR="${SRV_MYSQLD_DATADIR[$id]}"
    MYSQLD_TMPDIR="${SRV_MYSQLD_TMPDIR[$id]}"
    MYSQLD_PIDFILE="${SRV_MYSQLD_PIDFILE[$id]}"
    MYSQLD_ERRFILE="${SRV_MYSQLD_ERRFILE[$id]}"
    MYSQLD_PORT="${SRV_MYSQLD_PORT[$id]}"
    MYSQLD_SOCKET="${SRV_MYSQLD_SOCKET[$id]}"

    MYSQL_ARGS="--defaults-file=$MYSQLD_VARDIR/my.cnf "
    MYSQLD_ARGS="--defaults-file=$MYSQLD_VARDIR/my.cnf ${MYSQLD_EXTRA_ARGS}"
    if [ "`whoami`" = "root" ]
    then
	MYSQLD_ARGS="$MYSQLD_ARGS --user=root"
    fi

    IB_ARGS="--defaults-file=$MYSQLD_VARDIR/my.cnf --ibbackup=$XB_BIN"
    XB_ARGS="--defaults-file=$MYSQLD_VARDIR/my.cnf"

    # Some aliases for compatibility, as tests use the following names
    topdir="$MYSQLD_VARDIR"
    mysql_datadir="$MYSQLD_DATADIR"
    mysql_tmpdir="$MYSQLD_TMPDIR"
    mysql_socket="$MYSQLD_SOCKET"
}

########################################################################
# Start server with the id specified as the first argument
########################################################################
function start_server_with_id()
{
    local id=$1
    shift

    vlog "Starting server with id=$id..."

    init_server_variables $id
    switch_server $id

    if [ ! -d "$MYSQLD_VARDIR" ]
    then
	vlog "Creating server root directory: $MYSQLD_VARDIR"
	mkdir "$MYSQLD_VARDIR"
    fi
    if [ ! -d "$MYSQLD_TMPDIR" ]
    then
	vlog "Creating server temporary directory: $MYSQLD_TMPDIR"
	mkdir "$MYSQLD_TMPDIR"
    fi

    # Create the configuration file used by mysql_install_db, the server
    # and the xtrabackup binary
    cat > ${MYSQLD_VARDIR}/my.cnf <<EOF
[mysqld]
socket=${MYSQLD_SOCKET}
port=${MYSQLD_PORT}
server-id=$id
basedir=${MYSQL_BASEDIR}
datadir=${MYSQLD_DATADIR}
tmpdir=${MYSQLD_TMPDIR}
log-error=${MYSQLD_ERRFILE}
log-bin=mysql-bin
relay-log=mysql-relay-bin
pid-file=${MYSQLD_PIDFILE}
replicate-ignore-db=mysql
${MYSQLD_EXTRA_MY_CNF_OPTS:-}

[client]
socket=${MYSQLD_SOCKET}
user=root
EOF

    # Create datadir and call mysql_install_db if it doesn't exist
    if [ ! -d "$MYSQLD_DATADIR" ]
    then
	vlog "Creating server data directory: $MYSQLD_DATADIR"
	mkdir -p "$MYSQLD_DATADIR"

	# Reserve 900 series for SST nodes
        if [[ $id -lt 900 ]];then
            call_mysql_install_db
        else 
            vlog "Skiping mysql_install_db of node $id for SST"
        fi
    fi

    # Start the server
    echo "Starting ${MYSQLD} ${MYSQLD_ARGS} $* "
    ${MYSQLD} ${MYSQLD_ARGS} $* &
    if ! mysql_ping
    then
        die "Can't start the server!"
    fi
    vlog "Server with id=$id has been started on port $MYSQLD_PORT, \
socket $MYSQLD_SOCKET"
}

########################################################################
# Stop server with the id specified as the first argument.  The server 
# is stopped in the fastest possible way.
########################################################################
function stop_server_with_id()
{
    local id=$1
    switch_server $id

    vlog "Killing server with id=$id..."

    if [ -f "${MYSQLD_PIDFILE}" ]
    then
        kill -9 `cat ${MYSQLD_PIDFILE}`
        rm -f ${MYSQLD_PIDFILE}
    else
        vlog "Server PID file '${MYSQLD_PIDFILE}' doesn't exist!"
    fi

    # Reset XB_ARGS so we can call xtrabackup in tests even without starting the
    # server
    XB_ARGS="--no-defaults"

    # unlock the port number
    free_reserved_port $MYSQLD_PORT

    reset_server_variables $id
}

########################################################################
# Start server with id=1 and additional command line arguments
# (if specified)
########################################################################
function start_server()
{
    start_server_with_id 1 $*
}

########################################################################
# Stop server with id=1
########################################################################
function stop_server()
{
    stop_server_with_id 1
}

########################################################################
# Shutdown cleanly server specified with the first argument
########################################################################
function shutdown_server_with_id()
{
    local id=$1
    switch_server $id

    vlog "Shutting down server with id=$id..."

    if [ -f "${MYSQLD_PIDFILE}" ]
    then
        ${MYSQLADMIN} ${MYSQL_ARGS} shutdown
    else
        vlog "Server PID file '${MYSQLD_PIDFILE}' doesn't exist!"
    fi

    # unlock the port number
    free_reserved_port $MYSQLD_PORT

    reset_server_variables $id
}

########################################################################
# Shutdown server with id=1 cleanly
########################################################################
function shutdown_server()
{
    shutdown_server_with_id 1
}

########################################################################
# Force a checkpoint for a server specified with the first argument
########################################################################
function force_checkpoint_with_server_id()
{
    local id=$1
    shift

    switch_server $id

    vlog "Forcing a checkpoint for server #$id"

    shutdown_server_with_id $id
    start_server_with_id $id $*
}

########################################################################
# Force a checkpoint for server id=1
########################################################################
function force_checkpoint()
{
    force_checkpoint_with_server_id 1 $*
}

########################################################################
# Configure a specified server as a slave
# Synopsis:
#   setup_slave <slave_id> <master_id>
#########################################################################
function setup_slave()
{
    local slave_id=$1
    local master_id=$2

    vlog "Setting up server #$slave_id as a slave of server #$master_id"

    switch_server $slave_id

    run_cmd $MYSQL $MYSQL_ARGS <<EOF
CHANGE MASTER TO
  MASTER_HOST='localhost',
  MASTER_USER='root',
  MASTER_PORT=${SRV_MYSQLD_PORT[$master_id]};

START SLAVE
EOF
}

########################################################################
# Wait until slave catches up with master.
# The timeout is hardcoded to 300 seconds
#
# Synopsis:
#   sync_slave_with_master <slave_id> <master_id>
#########################################################################
function sync_slave_with_master()
{
    local slave_id=$1
    local master_id=$2
    local count
    local master_file
    local master_pos

    vlog "Syncing slave (id=#$slave_id) with master (id=#$master_id)"

    # Get master log pos
    switch_server $master_id
    count=0
    while read line; do
      	if [ $count -eq 1 ] # File:
      	then
      	    master_file=`echo "$line" | sed s/File://`
      	elif [ $count -eq 2 ] # Position:
      	then
      	    master_pos=`echo "$line" | sed s/Position://`
      	fi
      	count=$((count+1))
    done <<< "`run_cmd $MYSQL $MYSQL_ARGS -Nse 'SHOW MASTER STATUS\G' mysql`"

    echo "master_file=$master_file, master_pos=$master_pos"

    # Wait for the slave SQL thread to catch up
    switch_server $slave_id

    run_cmd $MYSQL $MYSQL_ARGS <<EOF
SELECT MASTER_POS_WAIT('$master_file', $master_pos, 300);
EOF
}

########################################################################
# Prints checksum for a given table.
# Expects 2 arguments: $1 is the DB name and $2 is the table to checksum
########################################################################
function checksum_table()
{
    $MYSQL $MYSQL_ARGS -Ns -e "CHECKSUM TABLE $2 EXTENDED" $1 | awk {'print $2'}
}

##########################################################################
# Dumps a given database using mysqldump                                 #
##########################################################################
function record_db_state()
{
    $MYSQLDUMP $MYSQL_ARGS -t --compact $1 >"$topdir/tmp/$1_old.sql"
}


##########################################################################
# Compares the current dump of a given database with a state previously  #
# captured with record_db_state().					 #
##########################################################################
function verify_db_state()
{
    $MYSQLDUMP $MYSQL_ARGS -t --compact $1 >"$topdir/tmp/$1_new.sql"
    diff -u "$topdir/tmp/$1_old.sql" "$topdir/tmp/$1_new.sql"
}

########################################################################
# Workarounds for a bug in grep 2.10 when grep -q file > file would
# result in a failure.
########################################################################
function grep()
{
    command grep "$@" | cat
    return ${PIPESTATUS[0]}
}

function egrep()
{
    command egrep "$@" | cat
    return ${PIPESTATUS[0]}
}

readonly xb_performed_bmp_inc_backup="xtrabackup: using the full scan for incremental backup"
readonly xb_performed_full_scan_inc_backup="xtrabackup: using the changed page bitmap"

####################################################
# Helper functions for testing incremental backups #
####################################################
function check_full_scan_inc_backup()
{
    if ! grep -q "$xb_performed_bmp_inc_backup" $OUTFILE ;
    then
        vlog "xtrabackup did not perform a full scan for the incremental backup."
        exit -1
    fi
    if grep -q "$xb_performed_full_scan_inc_backup" $OUTFILE ;
    then
        vlog "xtrabackup appeared to use bitmaps instead of full scan for the incremental backup."
        exit -1
    fi
}

function check_bitmap_inc_backup()
{
    if ! grep -q "$xb_performed_full_scan_inc_backup" $OUTFILE ;
    then
        vlog "xtrabackup did not use bitmaps for the incremental backup."
        exit -1
    fi
    if grep -q "$xb_performed_bmp_inc_backup" $OUTFILE ;
    then
        vlog "xtrabackup used a full scan instead of bitmaps for the incremental backup."
        exit -1
    fi
}

##############################################################
# Helper functions for xtrabackup process suspend and resume #
##############################################################
function wait_for_xb_to_suspend()
{
    local file=$1
    local i=0
    echo "Waiting for $file to be created"
    while [ ! -r $file ]
    do
        sleep 1
        i=$((i+1))
        echo "Waited $i seconds for xtrabackup_suspended to be created"
    done
}

function resume_suspended_xb()
{
    local file=$1
    echo "Removing $file"
    rm -f $file
}

# To avoid unbound variable error when no server have been started
SRV_MYSQLD_IDS=
