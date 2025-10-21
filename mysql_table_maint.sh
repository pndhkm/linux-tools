#!/bin/bash
# mysql_table_maint.sh
# Usage: ./mysql_table_maint.sh dbname/tablename

LOG_FILE="/var/log/mysql_table_maint.log"
TMP_LOG="/tmp/mysql_table_check_tmp.log"

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
    mysql -u root -Nse "SHOW DATABASES LIKE '$DB';" | grep -qw "$DB"
}

table_exists() {
    mysql -u root -Nse "SHOW TABLES FROM \`$DB\` LIKE '$TABLE';" | grep -qw "$TABLE"
}

# --- Functions ---

check_table() {
    local ts msg
    ts="[$(date '+%Y-%m-%d %H:%M:%S')]"

    if ! db_exists; then
        msg="$ts Error: Database '$DB' does not exist."
        echo "$msg" | tee -a "$LOG_FILE"
        return
    fi

    if ! table_exists; then
        msg="$ts Error: Table '$DB.$TABLE' does not exist."
        echo "$msg" | tee -a "$LOG_FILE"
        return
    fi

    echo "$ts Checking table: $DB.$TABLE ..." | tee -a "$LOG_FILE"

    mysql -u root -e "CHECK TABLE \`$TABLE\` EXTENDED;" "$DB" 2>&1 > "$TMP_LOG"

    local summary
    summary=$(awk 'NR>1 {printf "%s | %s | %s | %s", $1, $2, $3, $4}' "$TMP_LOG")

    if grep -Eiq "error|warning|corrupt|crash" "$TMP_LOG"; then
        msg="$ts Result: ISSUE DETECTED | $summary"
    else
        msg="$ts Result: OK | $summary"
    fi

    echo "$msg" | tee -a "$LOG_FILE"
    rm -f "$TMP_LOG"
}

repair_table() {
    local ts msg
    ts="[$(date '+%Y-%m-%d %H:%M:%S')]"

    if ! db_exists; then
        msg="$ts Error: Database '$DB' does not exist."
        echo "$msg" | tee -a "$LOG_FILE"
        return
    fi

    if ! table_exists; then
        msg="$ts Error: Table '$DB.$TABLE' does not exist."
        echo "$msg" | tee -a "$LOG_FILE"
        return
    fi

    echo "$ts Repairing table: $DB.$TABLE ..." | tee -a "$LOG_FILE"

    mysql -u root -e "REPAIR TABLE \`$TABLE\`;" "$DB" 2>&1 > "$TMP_LOG"

    local summary
    summary=$(awk 'NR>1 {printf "%s | %s | %s | %s", $1, $2, $3, $4}' "$TMP_LOG")

    if grep -Eiq "error|warning|corrupt|crash" "$TMP_LOG"; then
        msg="$ts Result: REPAIR ISSUE | $summary"
    else
        msg="$ts Result: REPAIR OK | $summary"
    fi

    echo "$msg" | tee -a "$LOG_FILE"
    rm -f "$TMP_LOG"
}

convert_innodb() {
    local ts msg
    ts="[$(date '+%Y-%m-%d %H:%M:%S')]"

    if ! db_exists; then
        msg="$ts Error: Database '$DB' does not exist."
        echo "$msg" | tee -a "$LOG_FILE"
        return
    fi

    if ! table_exists; then
        msg="$ts Error: Table '$DB.$TABLE' does not exist."
        echo "$msg" | tee -a "$LOG_FILE"
        return
    fi

    ENGINE=$(mysql -u root -Nse "SELECT ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DB' AND TABLE_NAME='$TABLE';")

    if [ "$ENGINE" == "InnoDB" ]; then
        msg="$ts Info: $DB.$TABLE is already InnoDB. No conversion needed."
        echo "$msg" | tee -a "$LOG_FILE"
        return
    fi

    echo "$ts Info: $DB.$TABLE currently using $ENGINE engine." | tee -a "$LOG_FILE"
    read -rp "Convert to InnoDB? [y/N]: " confirm
    confirm=${confirm:-N}

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "$ts Converting $DB.$TABLE to InnoDB ..." | tee -a "$LOG_FILE"
        mysql -u root -e "ALTER TABLE \`$TABLE\` ENGINE=InnoDB;" "$DB" 2>&1 > "$TMP_LOG"

        if grep -Eiq "error|warning" "$TMP_LOG"; then
            msg="$ts Result: CONVERSION FAILED | $DB.$TABLE"
        else
            msg="$ts Result: CONVERSION SUCCESS | $DB.$TABLE"
        fi
        echo "$msg" | tee -a "$LOG_FILE"
    else
        echo "$ts Conversion canceled." | tee -a "$LOG_FILE"
    fi

    rm -f "$TMP_LOG"
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
