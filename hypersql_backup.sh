#!/bin/sh
PATH=/usr/pgsql-14/bin/:$PATH
DATETIME=`date +%Y%m%d_%H%M%S`

# LOGGING
function logging() {
	if [[ $BAK_LOG_ENABLE =~ [Yy] ]]; then
		LOGDATE=`date +%Y-%m-%d\ %H:%M:%S`
		echo -e "[$LOGDATE] $1" >> ${BAK_LOG_DIR}/backup-${DATETIME}.log;
	fi
}

function get_DB_info() {
    sizeSum=0
                echo -e "\n| Database List "
                echo "-----------------"
                logging "\n| Database List "
                logging "-----------------"
    shopt -s lastpipe
    psql --host=${CON_SOCKET_DIR} --port=${CON_PORT} --username=${CON_USER} -x -A -l | grep Name | while read line
    do
        psql --host=${CON_SOCKET_DIR} --port=${CON_PORT} --username=${CON_USER} -xAtc "SELECT pg_database_size('${line:5}') AS size" | read size
                echo "| ${line:5} "$((${size:5}/1024/1024))"MB"
                logging "| ${line:5} "$((${size:5}/1024/1024))"MB"
        sizeSum=$((${sizeSum} + ${size:5}))
    done
                echo "Total Database Size : "$((${sizeSum}/1024/1024))"MB"
                logging "Total Database Size : "$((${sizeSum}/1024/1024))"MB"
}

# CACLUATE PERIOD
function calPeriod() {
# $1 = period
case $1 in
	1) echo "0 0 * * * " ;;
	2) echo "* * * * 7 " ;;
	3) echo "* * 1 * * " ;;
esac
}

# EDIT CRONTABLE & INSTALL
function editCron() {
	crontab -l > ${BAK_DIR}/crontmpf
	sed -i "/hypersql_backup/d" ${BAK_DIR}/crontmpf
	CRON_CMD=$(calPeriod $1)
	CRON_CMD="$CRON_CMD $2"
	echo "$CRON_CMD" >> ${BAK_DIR}/crontmpf
	crontab -r
	crontab -i ${BAK_DIR}/crontmpf
	logging "$CRON_CMD"
	rm -rf ${BAK_DIR}

}

# ECHO USAGE
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
	echo "Usage: $0 <CONFIG FILE> [OPTION]"
	exit 1
fi

CONFIG_PATH="$1"
SHELL_PATH="$0"
# GET CONFIGURATION
if [[ -e ${1} ]] && [[ -s ${1} ]] ; then
	if [[ ${1:0:1} == . ]] && [[ ! ${1:0:1} == / ]]; then
		CRD=`pwd`
		. $CRD/${1}
		CONFIG_PATH="$CRD/${1}"
	elif [[ ! ${1} == */* ]]; then
		. ./${1}
		CRD=`pwd`
		CONFIG_PATH="$CRD/${1}"
	else
		. ${1}
	fi
else
	echo "[ERR:00] : Configuration file does not exist."	
	exit 1
fi

if [[ $# = 2 ]]; then
	case $2 in
		--immediately)
			BAK_PERIOD=0 ;;
		--getinfo)
			get_DB_info
			exit 0 ;;
	esac
fi



# GET SHELL LOCATION
if [[ ! ${0:0:1} == . ]]; then
	SHELL_PATH=$0
elif [[ ! ${0} == */* ]]; then
	SHELL_PATH=$CRD/${0:1}
else
	SHELL_PATH=$CRD/${0:1}
fi

# SET LOG
if [[ ${BAK_LOG_ENABLE} =~ [Yy] ]] ; then
	touch ${BAK_LOG_DIR}/checkfile
	if [[ ! -d ${BAK_LOG_DIR} ]] || [[ ! -w ${BAK_LOG_DIR}/checkfile ]]; then
		echo "Please Check Log directory... Ex) Permission"
		exit 1
	else
		rm -f ${BAK_LOG_DIR}/checkfile
		echo "${BAK_LOG_DIR}/backup-${DATETIME}.log"
		BAK_OPTS="$BAK_OPTS --verbose "
	fi
fi

logging "Start logging..."

# CHECK & SET BAK_DIR
touch ${BAK_DIR}/checkfile
if [[ ! -d ${BAK_DIR} ]] || [[ ! -w ${BAK_DIR}/checkfile ]]; then
                echo "Please Check Backup directory... Ex) Permission"
                logging "Please Check Backup directory... Ex) Permission"
                exit 1
else
		rm -f ${BAK_DIR}/checkfile
		BAK_DIR=${BAK_DIR}/backup-${DATETIME}
		mkdir ${BAK_DIR}
		BAK_OPTS="${BAK_OPTS} -D ${BAK_DIR}" 
fi

# SET PERIOD
if [[ ! $BAK_PERIOD =~ ^[0-3] ]] || [[ ${#BAK_PERIOD} -gt 1 ]]; then
	echo "[ERR:02] : Please, Input valid period in configuration file"
	logging "[ERR:02] : Please, Input valid period in configuration file"
	exit 1
fi


# SET COMPRESS
if [[ ${#BAK_COMPRESS_LEVEL} -gt 0 ]] && [[ ${BAK_COMPRESS_ENABLE} == Y ]] || [[ ${BAK_COMPRESS_ENABLE} == y ]]; then
	BAK_OPTS="$BAK_OPTS -Ft --compress=$BAK_COMPRESS_LEVEL "
fi

# SET CHECKPOINT
if [[ ${BAK_CHECKPOINT_FAST} =~ [yY] ]] ; then
        BAK_OPTS="$BAK_OPTS --checkpoint=fast "
fi

# SET SYNC
if [[ ${BAK_ASYNC} =~ [yY] ]] ; then
	BAK_OPTS="$BAK_OPTS --no-sync "
fi


# SET CONNECTION
BAK_OPTS="-h ${CON_SOCKET_DIR} -p ${CON_PORT} -U ${CON_USER} $BAK_OPTS"


# SET LABEL
BAK_OPTS="$BAK_OPTS --label=${DATETIME}"

logging "$BAK_OPTS"
echo "$BAK_OPTS"
# BACKUP DATABASE CLUSTER
get_DB_info

case $BAK_PERIOD in
	0) pg_basebackup ${BAK_OPTS} >> ${BAK_LOG_DIR}/backup-${DATETIME}.log 2>&1
		echo "backup complete.." 
		logging "backup complete.." ;;
	*) editCron $BAK_PERIOD "$SHELL_PATH $CONFIG_PATH --immediately" 
		echo "backup reserverd.."
		logging "backup reserverd.." ;;
esac

