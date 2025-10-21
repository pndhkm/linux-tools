#!/bin/bash
# mysql_table_maint.sh
# Usage: ./mysql_table_maint.sh dbname/tablename

LOG_FILE="/var/log/mysql_table_maint.log"

if [ -z "$1" ]; then
    echo "Usage: $0 dbname/tablename"
    exit 1
fi

DB=$(echo "$1" | cut -d'/' -f1)
TABLE=$(echo "$1" | cut -d'/' -f2)

if [ -z "$DB" ] || [ -z "$TABLE" ]; then
    echo "Error: Invalid format. Use dbname/tablename"
    exit 1
fi

# --- Utility Checks ---

db_exists() {
    local result
    result=$(mysql -u root -Nse "SHOW DATABASES LIKE '$DB';" 2>/dev/null)
    [ "$result" == "$DB" ]
}

table_exists() {
    local result
    result=$(mysql -u root -Nse "SHOW TABLES FROM \`$DB\` LIKE '$TABLE';" 2>/dev/null)
    [ "$result" == "$TABLE" ]
}

log_event() {
    local message="$1"
    local ts
    ts=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$ts] $DB/$TABLE $message" >> "$LOG_FILE"
}

# --- Functions ---

check_table() {
    if ! db_exists; then
        echo "Error: Database '$DB' does not exist."
        log_event "Error: database not found"
        return 1
    fi
    if ! table_exists; then
        echo "Error: Table '$DB.$TABLE' does not exist."
        log_event "Error: table not found"
        return 1
    fi

    echo "Checking $DB.$TABLE ..."
    mysql -u root -Nse "CHECK TABLE \`$TABLE\` EXTENDED;" "$DB" 2>/dev/null > /tmp/mysql_check_tmp.log
    if [ $? -ne 0 ]; then
        echo "MySQL check command failed (connection or permission error)."
        log_event "MySQL check command failed"
        rm -f /tmp/mysql_check_tmp.log
        return 1
    fi

    echo ""
    echo "Result:"
    awk -F'\t' '{printf "  %-10s : %s\n", $3, $4}' /tmp/mysql_check_tmp.log

    local msg
    msg=$(awk -F'\t' '{print $4}' /tmp/mysql_check_tmp.log | grep -Evi 'Table|Op|Msg' | tail -n1)

    if grep -Eiq "error|warning|corrupt|crash" /tmp/mysql_check_tmp.log; then
        echo ""
        echo "Detected issues:"
        grep -Ei "error|warning|corrupt|crash" /tmp/mysql_check_tmp.log | sort | uniq | sed 's/^/  - /'
        log_event "$msg"
    else
        echo ""
        echo "Status: OK (no errors found)"
        log_event "Table OK"
    fi

    rm -f /tmp/mysql_check_tmp.log
    return 0
}

repair_table() {
    if ! db_exists; then
        echo "Error: Database '$DB' does not exist."
        log_event "Error: database not found"
        return 1
    fi
    if ! table_exists; then
        echo "Error: Table '$DB.$TABLE' does not exist."
        log_event "Error: table not found"
        return 1
    fi

    echo "Repairing $DB.$TABLE ..."
    mysql -u root -Nse "REPAIR TABLE \`$TABLE\`;" "$DB" 2>/dev/null > /tmp/mysql_repair_tmp.log
    if [ $? -ne 0 ]; then
        echo "Repair command failed (connection or permission error)."
        log_event "MySQL repair command failed"
        rm -f /tmp/mysql_repair_tmp.log
        return 1
    fi

    echo ""
    echo "Result:"
    awk -F'\t' '{printf "  %-10s : %s\n", $3, $4}' /tmp/mysql_repair_tmp.log

    local msg
    msg=$(awk -F'\t' '{print $4}' /tmp/mysql_repair_tmp.log | grep -Evi 'Table|Op|Msg' | tail -n1)
    [ -z "$msg" ] && msg="repair status: skipped"
    log_event "$msg"

    rm -f /tmp/mysql_repair_tmp.log
    return 0
}

convert_innodb() {
    if ! db_exists; then
        echo "Error: Database '$DB' does not exist."
        log_event "Error: database not found"
        return 1
    fi
    if ! table_exists; then
        echo "Error: Table '$DB.$TABLE' does not exist."
        log_event "Error: table not found"
        return 1
    fi

    ENGINE=$(mysql -u root -Nse "SELECT ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DB' AND TABLE_NAME='$TABLE';" 2>/dev/null)
    if [ -z "$ENGINE" ]; then
        echo "Error: Unable to detect engine (check permissions)."
        log_event "Error: unable to detect engine"
        return 1
    fi

    if [ "$ENGINE" == "InnoDB" ]; then
        echo "$DB.$TABLE is already InnoDB. No conversion needed."
        log_event "Already InnoDB"
        return 0
    fi

    echo "$DB.$TABLE is currently using $ENGINE engine."
    read -rp "Convert to InnoDB? [y/N]: " confirm
    confirm=${confirm:-N}

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "Converting $DB.$TABLE to InnoDB ..."
        if mysql -u root -e "ALTER TABLE \`$TABLE\` ENGINE=InnoDB;" "$DB" 2>/dev/null; then
            echo "Conversion completed."
            log_event "Converted to InnoDB"
        else
            echo "Conversion failed (check MySQL error)."
            log_event "Conversion failed"
            return 1
        fi
    else
        echo "Conversion canceled."
        log_event "Conversion canceled"
    fi
    return 0
}

# --- Main Loop ---
while true; do
    echo ""
    echo "Select action for $DB.$TABLE:"
    echo "1) Check table"
    echo "2) Repair table"
    echo "3) Convert to InnoDB"
    echo "0) Exit"
    read -rp "Enter option [0-3]: " OPTION

    case "$OPTION" in
        1)
            check_table
            ;;
        2)
            repair_table
            ;;
        3)
            convert_innodb
            ;;
        0)
            echo "Exiting."
            break
            ;;
        *)
            echo "Invalid option."
            ;;
    esac
done
