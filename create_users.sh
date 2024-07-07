#!/bin/bash

# Log file location
LOG_FILE="/var/log/user_management.log"
# Secure password storage location
SECURE_DIR="/var/secure"
PASSWORD_FILE="$SECURE_DIR/user_passwords.txt"

# Ensure the secure directory exists
mkdir -p $SECURE_DIR || { echo "Failed to create $SECURE_DIR"; exit 1; }
chmod 700 $SECURE_DIR

# Function to generate a random password
generate_password() {
    openssl rand -base64 12
}

# Function to log actions with timestamp
log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') : $1" >> $LOG_FILE
}

# Check if the text file with usernames and groups is provided as an argument
if [ -z "$1" ]; then
    echo "Usage: $0 <user_list_file>"
    exit 1
fi

# Read the file line by line
while IFS=';' read -r username groups; do
    username=$(echo "$username" | xargs)  # Remove any surrounding whitespace
    groups=$(echo "$groups" | xargs)      # Remove any surrounding whitespace
    
    # Skip empty lines or lines without a valid username
    if [ -z "$username" ]; then
        continue
    fi

    # Create user group if it does not exist
    if ! getent group "$username" > /dev/null; then
        groupadd "$username" || { log_action "Failed to create group $username"; continue; }
        log_action "Group $username created."
    else
        log_action "Group $username already exists."
    fi

    # Process additional groups
    additional_groups=""
    if [ -n "$groups" ]; then
        IFS=',' read -ra group_array <<< "$groups"
        for group in "${group_array[@]}"; do
            group=$(echo "$group" | xargs)
            if ! getent group "$group" > /dev/null; then
                groupadd "$group" || { log_action "Failed to create group $group"; continue; }
                log_action "Group $group created."
            fi
            additional_groups+="$group,"
        done
        additional_groups=${additional_groups%,}  # Remove trailing comma
    fi

    # Create user if it does not exist
    if ! id -u "$username" > /dev/null 2>&1; then
        password=$(generate_password)
        if [ -n "$additional_groups" ]; then
            useradd -m -g "$username" -G "$additional_groups" -s /bin/bash "$username" || { log_action "Failed to create user $username"; continue; }
        else
            useradd -m -g "$username" -s /bin/bash "$username" || { log_action "Failed to create user $username"; continue; }
        fi
        echo "$username:$password" | chpasswd || { log_action "Failed to set password for $username"; continue; }
        log_action "User $username created with groups: $additional_groups."
        echo "$username:$password" >> "$PASSWORD_FILE"
        chmod 600 "$PASSWORD_FILE"
        log_action "Password for $username stored securely."
    else
        log_action "User $username already exists."
    fi

    # Ensure home directory exists and set permissions and ownership
    if [ -d "/home/$username" ]; then
        chown -R "$username:$username" "/home/$username" || log_action "Failed to set ownership for /home/$username"
        chmod 700 "/home/$username" || log_action "Failed to set permissions for /home/$username"
        log_action "Permissions set for /home/$username."
    else
        log_action "Home directory for $username does not exist."
    fi
done < "$1"

log_action "User creation process completed."
echo "User creation process completed. Passwords stored in $PASSWORD_FILE"
echo "Please ensure to distribute passwords securely and delete $PASSWORD_FILE after distribution."
