
Вот улучшенная версия скрипта с подробным описанием для Git (в виде README.md), который можно добавить в репозиторий:

```markdown
# Proxmox Debian 12 Docker Template Creator

Скрипт для автоматического создания шаблона виртуальной машины в Proxmox VE на базе Debian 12 (Bookworm) с предустановленным Docker.

## Особенности

- Автоматическая загрузка официального cloud-образа Debian 12
- Настройка оптимальных параметров ВМ (память, CPU, диск)
- Предустановка Docker и сопутствующих компонентов
- Настройка cloud-init для автоматической конфигурации
- Интеграция с QEMU Guest Agent
- Поддержка различных типов хранилищ (ZFS, LVM, local)
- Автоматическое определение пользователя и SSH ключей

## Требования

- Proxmox VE 7.x или новее
- Доступ к интернету с хоста Proxmox
- Права root для выполнения скрипта

## Параметры конфигурации

Все параметры задаются в начале скрипта:

```bash
VMID=9000                  # ID виртуальной машины
RAM=4096                   # Память в MB
CORES=4                    # Количество ядер CPU
DISK="30G"                 # Размер диска
CPU="host"                 # Тип процессора
IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
TIMEZONE="Europe/Moscow"   # Часовой пояс
```

## Установка

1. Клонируйте репозиторий или скачайте скрипт:

```bash
git clone https://github.com/lukomsky85/proxmox-debian-docker-template.git
cd proxmox-debian-docker-template
```

2. Сделайте скрипт исполняемым:

```bash
chmod +x create_debian_docker_template.sh
```

3. Запустите скрипт с правами root:

```bash
sudo ./create_debian_docker_template.sh
```

## Что делает скрипт

1. Проверяет права root
2. Определяет доступное хранилище
3. Находит пользователя и SSH ключи
4. Скачивает образ Debian 12 (если не существует)
5. Создает новую виртуальную машину с указанными параметрами
6. Настраивает cloud-init для автоматической установки:
   - Docker CE
   - Docker Compose
   - Полезные утилиты (htop, vim, tmux и др.)
   - QEMU Guest Agent
7. Настраивает часовой пояс
8. Отключает root-доступ по SSH
9. Преобразует ВМ в шаблон

## Использование шаблона

После создания шаблона вы можете клонировать его для новых ВМ:

```bash
qm clone 9000 123 --name my-new-vm
```

Где:
- `9000` - ID шаблона
- `123` - ID новой ВМ
- `my-new-vm` - имя новой ВМ

## Логирование

Скрипт выводит подробную информацию о ходе выполнения:
- `[INFO]` - информационные сообщения
- `[WARNING]` - предупреждения
- `[ERROR]` - критические ошибки

## Кастомизация

Вы можете изменить следующие параметры:

1. **Параметры ВМ** - измените переменные в начале скрипта
2. **Устанавливаемые пакеты** - отредактируйте раздел `packages` в cloud-init конфигурации
3. **Post-install скрипты** - добавьте свои команды в раздел `runcmd`

## Пример cloud-init конфигурации

```yaml
#cloud-config
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - docker-ce
  - docker-compose-plugin
  # Дополнительные пакеты...
  
runcmd:
  # Ваши custom команды
  - systemctl enable docker
```
