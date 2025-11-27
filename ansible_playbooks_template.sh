#!/usr/bin/env bash

set -e

PROJECT_NAME=${1:-ansible-project}

echo "Creating Ansible project: $PROJECT_NAME"
mkdir -p "$PROJECT_NAME"

# Inventory
mkdir -p "$PROJECT_NAME/inventory"
cat > "$PROJECT_NAME/inventory/hosts.ini" <<'EOF'
[appservers]
app01 ansible_host=10.10.10.11 env=prod
app02 ansible_host=10.10.10.12 env=dev
EOF

# Setup ansible.cfg
cat > "$PROJECT_NAME/ansible.cfg" <<'EOF'
[defaults]
host_key_checking = False
roles_path = roles
library = library
retry_files_save_path=retries
EOF

# Create Retries directory
mkdir -p "$PROJECT_NAME/retries"

# Group vars
mkdir -p "$PROJECT_NAME/group_vars"
cat > "$PROJECT_NAME/group_vars/appservers.yml" <<'EOF'
app_name: "backend_service"
listen_port: 8080
log_level: "info"

env_config:
  prod:
    db_host: "10.1.1.10"
    db_port: 5432
  dev:
    db_host: "10.1.1.20"
    db_port: 5432
EOF

# Playbook directory
mkdir -p "$PROJECT_NAME/plays"
cat > "$PROJECT_NAME/plays/setup-example.yml" <<'EOF'
- hosts: appservers
  become: yes
  gather_facts: yes
  roles:
    - example
EOF

# Roles
mkdir -p "$PROJECT_NAME/roles/example/tasks"
mkdir -p "$PROJECT_NAME/roles/example/handlers"
mkdir -p "$PROJECT_NAME/roles/example/templates"

# Tasks
cat > "$PROJECT_NAME/roles/example/tasks/main.yml" <<'EOF'
- name: Render application configuration
  template:
    src: example.conf.j2
    dest: /etc/example/example.conf
    mode: "0644"
  notify:
    - Restart apache

- name: Ensure service directory exists
  file:
    path: /etc/example
    state: directory
    mode: "0755"
EOF

# Handler
cat > "$PROJECT_NAME/roles/example/handlers/main.yml" <<'EOF'
- name: Restart apache
  ansible.builtin.service:
    name: httpd
    state: restarted
EOF

# Template file
cat > "$PROJECT_NAME/roles/example/templates/example.conf.j2" <<'EOF'
[service]
name = {{ app_name }}
port = {{ listen_port }}
log_level = {{ log_level }}

[database]
host = {{ env_config[hostvars[inventory_hostname].env].db_host }}
port = {{ env_config[hostvars[inventory_hostname].env].db_port }}
EOF

echo "Project created successfully."
