
# User Management Automation (UMA)

This project contains `create_users.sh`, a Bash script designed to automate Linux user provisioning using a simple input file.  
It is built as part of a SysOps/DevOps challenge to standardize, secure, and automate user account creation.


# How to install

git clone https://github.com/siyonisarvagode7/UMA.git 

cd LINUX

## Features
The script performs the following automated operations:

- Reads user information from a file formatted as:


username;group1,group2,group3

- Skips comments and empty lines.
- Removes unnecessary whitespace automatically.
- Creates a **primary group** named after the username.
- Creates supplementary groups if they do not exist.
- Creates a user (or updates an existing user).
- Ensures a home directory exists (`/home/username`) with:
- Correct owner
- Secure permissions (`700`)
- Generates a **secure 12-character random password**.
- Assigns the password to the user.
- Stores credentials in:


/var/secure/user_passwords.txt

(permissions enforced as `600`)
 Logs all actions (success, errors, skips) into:


/var/log/user_management.log

 Uses strict Bash modes for safety (`errexit`, `nounset`, `pipefail`).

 **Note:** The script must be run as root:  
 `sudo ./create_users.sh users.txt`


##  Example Input File (`users.txt`)


User account and group mappings

light; sudo,dev,www-data
siyoni; sudo
manoj; dev,www-data

Lines starting with # are ignored

##  Usage

Make the script executable:

bash
chmod +x create_users.sh


Run it with:

sudo ./create_users.sh users.txt

 How the Script Works (Internally)
# Input Processing

Reads the input file line-by-line.

Skips:

Empty lines

Lines starting with #

Splits valid lines into:

username

group list (comma-separated)

# Group Handling

Ensures the primary group (same as username) exists.

Creates supplementary groups if missing.

# User Handling

If the user already exists:

Updates primary group if needed.

Adds missing supplementary groups.

Ensures home directory exists and is secured.

If user does not exist:

Creates user with:

Home directory

Bash shell

Primary/supplementary groups

# Password Management

Generates a secure 12-character password using:

openssl rand or

/dev/urandom fallback

Assigns password via chpasswd.

Appends username:password to:

/var/secure/user_passwords.txt

# Logging

All events logged to /var/log/user_management.log with timestamps.

Uses a custom log() helper function.

 Security Considerations

Password file contains plaintext passwords — restricted to root using:

chmod 600 user_passwords.txt


Highly recommended after provisioning:

Rotate or delete stored passwords

Force password change at first login:

chage -d 0 <username>


Script must be executed with root privileges.

Logs do not contain passwords.

 Directory/Filesystem Paths Used
Purpose	Path
Store user credentials	/var/secure/user_passwords.txt
Log script actions	/var/log/user_management.log
User home directories	/home/<username>
Script input file	Custom path (e.g., users.txt)
 Testing

You can test using a sample file:

test1; sudo
test2; dev,www-data


Then run:

sudo ./create_users.sh sample_users.txt


Verify results:

cat /var/secure/user_passwords.txt
cat /var/log/user_management.log
ls -ld /home/test1

 Troubleshooting
# “Illegal option -o pipefail”

Run with bash explicitly:

sudo bash create_users.sh users.txt

# “command not found: openssl”

Script will fallback to /dev/urandom — no action needed.

# Permission denied errors

Ensure you are using sudo:

sudo ./create_users.sh users.txt

# Home directory not created

Check logs at:

sudo cat /var/log/user_management.log

 File Structure
UMA/
├── create_users.sh
├── users.txt
└── README.md
