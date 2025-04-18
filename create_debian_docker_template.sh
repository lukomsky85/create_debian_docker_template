#!/bin/bash

set -e

# Проверка прав root
if [ "$(id -u)" != "0" ]; then
   echo "Этот скрипт должен запускаться с правами root" >&2
   exit 1
fi

# Конфигурация
VMID=9000                  # ID виртуальной машины
RAM=4096                   # Память в MB
CORES=4                    # Количество ядер CPU
DISK="30G"                 # Размер диска
CPU="host"                 # Тип процессора
IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
IMAGE_NAME="debian-12-docker-template.qcow2"
TEMPLATE_NAME="debian-12-docker"
TIMEZONE="Europe/Moscow"   # Часовой пояс
USERNAME=""                # Имя пользователя (определится автоматически)

# Функция для определения хранилища
detect_storage() {
    if pvesm status | grep -q "local-zfs"; then
        echo "local-zfs"
    elif pvesm status | grep -q "local-lvm"; then
        echo "local-lvm"
    else
        echo "local"
    fi
}

# Определение хранилища
STORAGE=$(detect_storage)
echo "[INFO] Используется хранилище: $STORAGE"

# Определение пользователя
if [ -n "$SUDO_USER" ]; then
    USERNAME="$SUDO_USER"
else
    USERNAME=$(logname 2>/dev/null || echo "")
fi

if [ -z "$USERNAME" ] || [ "$USERNAME" = "root" ]; then
    read -p "Введите имя пользователя для шаблона: " USERNAME
    if [ -z "$USERNAME" ]; then
        echo "[ERROR] Имя пользователя не указано, выход."
        exit 1
    fi
fi

echo "[INFO] Создание шаблона ВМ для пользователя: $USERNAME"

# Поиск SSH ключей
SSH_KEY_PATH=""
if [ -f "/home/$USERNAME/.ssh/authorized_keys" ]; then
    SSH_KEY_PATH="/home/$USERNAME/.ssh/authorized_keys"
elif [ -f "/root/.ssh/authorized_keys" ]; then
    SSH_KEY_PATH="/root/.ssh/authorized_keys"
fi

if [ -n "$SSH_KEY_PATH" ]; then
    echo "[INFO] Найден SSH ключ: $SSH_KEY_PATH"
else
    echo "[WARNING] SSH ключи не найдены. Доступ по SSH нужно будет настроить вручную."
fi

# Подготовка образа
prepare_image() {
    echo "[INFO] Загрузка и подготовка образа..."
    if [ ! -f "$IMAGE_NAME" ]; then
        wget -q --show-progress "$IMAGE_URL" -O "$IMAGE_NAME"
    else
        echo "[INFO] Образ уже существует, повторная загрузка не требуется."
    fi
    
    # Проверка размера образа
    CURRENT_SIZE=$(qemu-img info "$IMAGE_NAME" | grep "virtual size" | awk '{print $3}')
    if [ "$CURRENT_SIZE" != "$DISK" ]; then
        echo "[INFO] Изменение размера диска на $DISK..."
        qemu-img resize "$IMAGE_NAME" "$DISK"
    else
        echo "[INFO] Размер диска уже соответствует требуемому ($DISK)."
    fi
    
    # Удаление существующей ВМ (если есть)
    if qm status $VMID >/dev/null 2>&1; then
        echo "[INFO] Удаление существующей ВМ с ID $VMID..."
        qm destroy $VMID
    fi
}

# Создание виртуальной машины
create_vm() {
    echo "[INFO] Создание виртуальной машины..."
    qm create "$VMID" \
        --name "$TEMPLATE_NAME" \
        --ostype l26 \
        --memory "$RAM" \
        --balloon 0 \
        --agent 1 \
        --bios ovmf \
        --machine q35 \
        --efidisk0 "$STORAGE:0,pre-enrolled-keys=0" \
        --cpu "$CPU" \
        --cores "$CORES" \
        --numa 1 \
        --vga serial0 \
        --serial0 socket \
        --net0 virtio,bridge=vmbr0,mtu=1

    echo "[INFO] Импорт диска..."
    qm importdisk "$VMID" "$IMAGE_NAME" "$STORAGE"
    
    if [[ "$STORAGE" == "local-zfs" ]]; then
        qm set "$VMID" --scsihw virtio-scsi-pci --virtio0 "$STORAGE:vm-$VMID-disk-1,discard=on,iothread=1"
    else
        qm set "$VMID" --scsihw virtio-scsi-pci --virtio0 "$STORAGE:vm-$VMID-disk-1,discard=on"
    fi
    
    qm set "$VMID" --boot order=virtio0
    qm set "$VMID" --scsi1 "$STORAGE:cloudinit"
}

# Настройка cloud-init
setup_cloud_init() {
    echo "[INFO] Настройка cloud-init..."
    mkdir -p /var/lib/vz/snippets
    
    cat << EOF > /var/lib/vz/snippets/debian-docker.yaml
#cloud-config
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - ca-certificates
  - curl
  - gnupg
  - lsb-release
  - vim
  - htop
  - iotop
  - tmux
  - git
  - wget
  - net-tools

users:
  - name: $USERNAME
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL

runcmd:
  - mkdir -p /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  - chmod a+r /etc/apt/keyrings/docker.gpg
  - echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(. /etc/os-release && echo "\$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  - apt-get update
  - apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  - usermod -aG docker $USERNAME
  - timedatectl set-timezone $TIMEZONE
  - systemctl enable --now qemu-guest-agent
  - sed -i 's/^PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
  - systemctl restart sshd
EOF

    qm set "$VMID" --cicustom "vendor=local:snippets/debian-docker.yaml"
    qm set "$VMID" --tags "debian,docker,cloudinit,template"
    qm set "$VMID" --ciuser "$USERNAME"
    
    if [ -n "$SSH_KEY_PATH" ]; then
        qm set "$VMID" --sshkeys "$SSH_KEY_PATH"
    fi
    
    qm set "$VMID" --ipconfig0 "ip=dhcp"
    qm set "$VMID" --description "Шаблон Debian 12 с Docker. Создан $(date +%Y-%m-%d)"
    
    echo "[INFO] Преобразование в шаблон..."
    qm template "$VMID"
}

# Основной процесс
echo "=== Начало создания шаблона ВМ ==="
prepare_image
create_vm
setup_cloud_init

# Очистка
if [ -f "$IMAGE_NAME" ]; then
    echo "[INFO] Удаление временного образа..."
    rm -f "$IMAGE_NAME"
fi

echo "=== Шаблон успешно создан! ==="
echo "ID шаблона: $VMID"
echo "Имя шаблона: $TEMPLATE_NAME"
echo "Для создания ВМ из этого шаблона выполните:"
echo "qm clone $VMID <новый_ID> --name <имя_новой_ВМ>"
