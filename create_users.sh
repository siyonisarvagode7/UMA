

set -o errexit
set -o nounset
set -o pipefail

INPUT_FILE="${1:-}"

# Constants
SECURE_DIR="/var/secure"
PASSWORD_FILE="$SECURE_DIR/user_passwords.txt"
LOG_FILE="/var/log/user_management.log"

# Ensure script is run as root
if [[ "$EUID" -ne 0 ]]; then
  echo "ERROR: This script must be run as root (or with sudo)." >&2
  exit 2
fi

# Simple logging function (timestamped) - writes to logfile and stdout
log() {
  local level="$1"
  local msg="$2"
  local timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "$timestamp [$level] $msg" | tee -a "$LOG_FILE"
}

# Initialize secure storage and log file, ensure correct permissions
init_files() {
  mkdir -p "$SECURE_DIR"
  touch "$PASSWORD_FILE"
  touch "$LOG_FILE"
  chmod 600 "$PASSWORD_FILE"
  chmod 600 "$LOG_FILE"
}

# Generate a secure random 12-character password
generate_password() {
  # Try to generate a 12-char password from a safe set
  # Fallbacks are included for portability
  local pass
  if command -v openssl >/dev/null 2>&1; then
    # openssl base64 may produce + and / which are fine; trim newlines; then take allowed chars
    pass=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9!@#$%&*()_+-=' | head -c 12)
  else
    # portable fallback using /dev/urandom
    pass=$(tr -dc 'A-Za-z0-9!@#$%&*()_+-=' < /dev/urandom | head -c 12 || true)
  fi

  # If generation failed or produced shorter string, additional fallback
  if [[ -z "$pass" || ${#pass} -lt 12 ]]; then
    pass=$(date +%s%N | sha256sum | base64 | tr -dc 'A-Za-z0-9' | head -c 12)
  fi
  printf '%s' "$pass"
}

# Ensure a group exists; create if missing
ensure_group() {
  local grp="$1"
  if [[ -z "$grp" ]]; then
    return
  fi
  if getent group "$grp" >/dev/null; then
    return
  fi
  if groupadd "$grp"; then
    log "INFO" "Created group: $grp"
  else
    log "ERROR" "Failed to create group: $grp"
  fi
}

# Ensure a user exists or create them
ensure_user() {
  local user="$1"
  local primary_group="$2"
  local sup_groups="$3"  # comma separated or empty

  if id "$user" &>/dev/null; then
    log "INFO" "User '$user' already exists. Will update groups/home/password as needed."
    # Ensure primary group matches (only if primary_group exists)
    if getent group "$primary_group" >/dev/null; then
      current_primary_gid=$(id -g "$user")
      current_primary_group=$(getent group "$current_primary_gid" | cut -d: -f1)
      if [[ "$current_primary_group" != "$primary_group" ]]; then
        usermod -g "$primary_group" "$user" && log "INFO" "Set primary group for $user -> $primary_group"
      fi
    fi

    # Add to supplementary groups if any
    if [[ -n "$sup_groups" ]]; then
      # usermod -a -G expects comma separated list
      usermod -a -G "$sup_groups" "$user" && log "INFO" "Added $user to supplementary groups: $sup_groups"
    fi
  else
    # Build useradd command
    local ua_cmd=(useradd -m -d "/home/$user" -s /bin/bash -g "$primary_group")
    if [[ -n "$sup_groups" ]]; then
      ua_cmd+=(-G "$sup_groups")
    fi
    ua_cmd+=("$user")
    if "${ua_cmd[@]}"; then
      log "INFO" "Created user: $user (primary group: $primary_group, supplementary: ${sup_groups:-none})"
    else
      log "ERROR" "Failed to create user: $user"
      return 1
    fi
  fi

  # Ensure home directory exists and set correct permissions/ownership
  if [[ ! -d "/home/$user" ]]; then
    mkdir -p "/home/$user" && log "INFO" "Created home directory: /home/$user"
  fi
  chown -R "$user":"$primary_group" "/home/$user" || log "WARN" "Failed to chown /home/$user"
  chmod 700 "/home/$user" || log "WARN" "Failed to chmod /home/$user"
}

# Main processing loop
process_file() {
  local f="$1"
  local line_no=0

  while IFS= read -r rawline || [[ -n "$rawline" ]]; do
    line_no=$((line_no + 1))
    # Trim leading/trailing whitespace
    line="$(echo "$rawline" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

    # Skip empty lines
    if [[ -z "$line" ]]; then
      continue
    fi

    # Skip comments (lines starting with # after trimming)
    if [[ "${line:0:1}" == "#" ]]; then
      log "INFO" "Skipping comment line $line_no"
      continue
    fi

    # Split into username and groups (on first ;)
    IFS=';' read -r user part_groups <<< "$line"
    # Remove all whitespace from username and group string
    user="$(echo "$user" | tr -d '[:space:]')"
    part_groups="$(echo "${part_groups:-}" | tr -d '[:space:]')"

    if [[ -z "$user" ]]; then
      log "ERROR" "Line $line_no: No username found. Skipping."
      continue
    fi

    # Build supplementary group list (csv) and ensure groups exist.
    sup_groups=""
    if [[ -n "$part_groups" ]]; then
      # split on comma and ensure each group exists
      IFS=',' read -r -a groups_arr <<< "$part_groups"
      local valid_groups=()
      for g in "${groups_arr[@]}"; do
        g_trimmed="$(echo "$g" | tr -d '[:space:]')"
        if [[ -n "$g_trimmed" ]]; then
          ensure_group "$g_trimmed"
          valid_groups+=("$g_trimmed")
        fi
      done
      # join back into comma separated string without spaces
      if [[ "${#valid_groups[@]}" -gt 0 ]]; then
        sup_groups="$(IFS=, ; echo "${valid_groups[*]}")"
      fi
    fi

    # Ensure primary group (same as username) exists
    ensure_group "$user"

    # Create or update user and handle home dir
    if ! ensure_user "$user" "$user" "$sup_groups"; then
      log "ERROR" "Line $line_no: Failed to create/update user $user"
      continue
    fi

    # Generate password and set it
    password="$(generate_password)"
    if printf '%s:%s\n' "$user" "$password" | chpasswd; then
      # Save to password file
      printf '%s:%s\n' "$user" "$password" >> "$PASSWORD_FILE"
      # Ensure password file perms (in case touched by other processes)
      chmod 600 "$PASSWORD_FILE"
      log "INFO" "Set password for user: $user and stored credentials."
      echo "Created/updated user '$user' with home /home/$user"
    else
      log "ERROR" "Failed to set password for user: $user"
      echo "ERROR: Failed to set password for user '$user'"
    fi

  done < "$f"
}

# ---------- main ----------
if [[ -z "$INPUT_FILE" ]]; then
  echo "Usage: sudo $0 <users_file>"
  exit 2
fi

if [[ ! -f "$INPUT_FILE" ]]; then
  echo "ERROR: Input file '$INPUT_FILE' not found." >&2
  exit 2
fi

init_files
log "INFO" "Starting user provisioning from '$INPUT_FILE'"

process_file "$INPUT_FILE"

log "INFO" "User provisioning completed."

exit 0
