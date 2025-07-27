#!/usr/bin/env bash

# Use this file if you used SOURCE instead of MASTER in setting up replication
# for example: if you use a command like below
# CHANGE REPLICATION SOURCE TO
#  SOURCE_HOST='source_host',
#  SOURCE_USER='replica_user',
#  SOURCE_PASSWORD='password',
#  SOURCE_LOG_FILE='mysql-bin.000023',
#  SOURCE_LOG_POS=154;

# instead of

# CHANGE REPLICATION MASTER TO
#  MASTER_HOST='source_host',
#  MASTER_USER='replica_user',
#  MASTER_PASSWORD='password',
#  MASTER_LOG_FILE='mysql-bin.000023',
#  MASTER_LOG_POS=154;


# Set mysql/mariadb login info 
 
# default is root but I set up admin user with less permission 
_user="admin"  
_pass="MariaDB_ADMIN_USER_PASSWORD"
_host="localhost"
 
_out="/tmp/mysql-status.$$"
_errs=()
_m_vars='Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master|Last_Errno'
_is_error_found="false"
_alert_limit=60
 
# Email settings 
FROM="smtp.out@cyberciti.biz"
TO="opmat01@yahoo.com"
 
# Grab keys and bash function  for pushover API 
#source ~/bin/cli_app.sh

 
# Send html email to "$TO" from "$FROM" 
html_email(){
    local SUBJECT="$HOSTNAME - mariadb/mysql slave server error(s)"
    local MSG=("$@")
    (
        echo "From: $FROM"
        echo "To: $TO"
        echo "Subject: $SUBJECT"
        echo "Content-Type: text/html"
        echo
 
        echo "<html>"
 
        echo "<p>Hostname : $HOSTNAME</p>"
        echo "<p>Date : $(date)</p>"
 
        echo "<h4>Errors:</h4>"
        echo "<pre>"
        ( IFS=$'\n'; echo "${MSG[*]}" )
        echo "</pre>"
 
        echo "<h4>SQL query raw values</h4>"
        echo "<pre>"
        echo "$(<${_out})"

        echo "</pre>"
 
        echo "<p>-- ${0}</p>"
 
        echo "</html>"
        echo
    ) | sendmail -f "$FROM" "$TO"
 
  
}
 
## main ##
## For mariadb version 10.5.1 or MySQL 8+, you can use
# -----------------------------------------------#
# SHOW ALL REPLICAS STATUS or SHOW REPLICA STATUS #
# ----------------------------------------------#
mysql -u "${_user}" -h "${_host}" -p"${_pass}" \
-e 'SHOW SLAVE STATUS \G;' \
| grep -E -i "${_m_vars}" > "${_out}" || html_email "Can't connect to local mysql/mariadb server."
 
 
IFS='|'

for v in $_m_vars
do
  value=$(awk -F':' -v m="${v}:" '$0 ~ m { gsub(/ /, "", $2); print $2 }' "${_out}")
  if [ "$v" == "Replica_IO_Running" ]
  then
      [[ "$value" != "Yes" ]] && { _errs=("${_errs[@]}" "<p>The I/O thread for reading the master's binary log not fo>
                     _is_error_found="true"; }
  fi
  if [ "$v" == "Replica_SQL_Running" ]
  then
      [[ "$value" !=  "Yes" ]] && { _errs=("${_errs[@]}" "<p>The SQL thread for executing events in the relay log is >
                     _is_error_found="true"; }
  fi
  if [ "$v" == "Seconds_Behind_Source" ]
  then
      [ "$value" == "NULL" ] && { _errs=("${_errs[@]}" "<p>The slave server is in undefined or unknown state ($v: $va>
                      _is_error_found="true"; }
      if [[ $value =~ ^[0-9]+$ ]]
      then
          [ "$value" -gt $_alert_limit ] && { _errs=("${_errs[@]}" "<p>The Slave server is behind the master for at l>
                                              _is_error_found="true"; }
      fi
  fi
  if [ "$v" == "Last_Errno" ]
  then
      [ "$value" -ne 0 ] && { _errs=("${_errs[@]}" "<p>The slave SQL thread receives an error ($v: $value</p>)");
                                _is_error_found="true"; }
  fi
 
done
 
# Send email and push message when error found 
[ $_is_error_found == "true" ] && html_email "${_errs[@]}"
 
# Cleanup 
[ -f "${_out}" ] && rm -f "${_out}"
