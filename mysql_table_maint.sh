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
    mysql -u root -Nse "SHOW DATABASES LIKE '$DB';" | grep -qw "$DB"
}

table_exists() {
    mysql -u root -Nse "SHOW TABLES FROM \`$DB\` LIKE '$TABLE';" | grep -qw "$TABLE"
}

# --- Functions ---

check_table() {
    if ! db_exists; then
        echo "Error: Database '$DB' does not exist."
        return
    fi
    if ! table_exists; then
        echo "Error: Table '$DB.$TABLE' does not exist."
        return
    fi

    echo "Checking $DB.$TABLE ..."
    mysql -u root -e "CHECK TABLE \`$TABLE\` EXTENDED;" "$DB" 2>&1 | tee /tmp/mysql_check_tmp.log

    echo ""
    echo "Unique log messages:"
    grep -Ei "error|warning|corrupt|crash" /tmp/mysql_check_tmp.log | sort | uniq || echo "No errors found."
    echo ""
    rm -f /tmp/mysql_check_tmp.log
}

repair_table() {
    if ! db_exists; then
        echo "Error: Database '$DB' does not exist."
        return
    fi
    if ! table_exists; then
        echo "Error: Table '$DB.$TABLE' does not exist."
        return
    fi

    echo "Repairing $DB.$TABLE ..."
    mysql -u root -e "REPAIR TABLE \`$TABLE\`;" "$DB"
}

convert_innodb() {
    if ! db_exists; then
        echo "Error: Database '$DB' does not exist."
        return
    fi
    if ! table_exists; then
        echo "Error: Table '$DB.$TABLE' does not exist."
        return
    fi

    ENGINE=$(mysql -u root -Nse "SELECT ENGINE FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DB' AND TABLE_NAME='$TABLE';")

    if [ "$ENGINE" == "InnoDB" ]; then
        echo "$DB.$TABLE is already InnoDB. No conversion needed."
        return
    fi

    echo "$DB.$TABLE is currently using $ENGINE engine."
    read -rp "Convert to InnoDB? [y/N]: " confirm
    confirm=${confirm:-N}

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "Converting $DB.$TABLE to InnoDB ..."
        mysql -u root -e "ALTER TABLE \`$TABLE\` ENGINE=InnoDB;" "$DB"
    else
        echo "Conversion canceled."
    fi
}

# --- Main Loop ---
while true; do
    echo ""
    echo "Select action for $DB.$TABLE:"
    echo "1) Check table (unique log)"
    echo "2) Repair table"
    echo "3) Convert to InnoDB"
    echo "0) Exit"
    read -rp "Enter option [0-3]: " OPTION

    case "$OPTION" in
        1)
            check_table | tee -a "$LOG_FILE"
            ;;
        2)
            repair_table | tee -a "$LOG_FILE"
            ;;
        3)
            convert_innodb | tee -a "$LOG_FILE"
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
