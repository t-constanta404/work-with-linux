#!/bin/bash
# Скрипт восстановления UEFI GRUB для Ubuntu
# Запускать из Live USB, загруженного в UEFI режиме

set -e

ROOT_LV="/dev/mapper/ubuntu--vg--1-ubuntu--lv"
EFI_PART="/dev/nvme2n1p1"
EFI_MOUNT="/mnt/root/boot/efi"
ROOT_MOUNT="/mnt/root"

echo "1. Проверка загрузки в UEFI режиме..."
if [ ! -d /sys/firmware/efi ]; then
    echo "Ошибка: Вы не в UEFI режиме. Перезагрузитесь в UEFI Live USB."
    exit 1
fi

echo "2. Создание точек монтирования..."
mkdir -p "$ROOT_MOUNT"
mkdir -p "$EFI_MOUNT"

echo "3. Монтирование root и EFI разделов..."
mount "$ROOT_LV" "$ROOT_MOUNT"
mount "$EFI_PART" "$EFI_MOUNT"

echo "4. Bind mounts для chroot..."
mount --bind /dev "$ROOT_MOUNT/dev"
mount --bind /proc "$ROOT_MOUNT/proc"
mount --bind /sys "$ROOT_MOUNT/sys"

echo "5. Проверка EFI раздела..."
if [ ! -d "$EFI_MOUNT/EFI" ]; then
    echo "Ошибка: Не найден каталог EFI на разделе $EFI_PART"
    exit 1
fi

echo "6. Вход в chroot..."
chroot "$ROOT_MOUNT" /bin/bash <<'EOF'
set -e

echo "6a. Пересборка initramfs..."
update-initramfs -u -k all

echo "6b. Очистка старых каталогов GRUB..."
if [ -d /boot/efi/EFI/ubuntu ]; then
    rm -rf /boot/efi/EFI/ubuntu
fi
mkdir -p /boot/efi/EFI/ubuntu

echo "6c. Установка GRUB заново..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Ubuntu --recheck

echo "6d. Генерация конфигурации GRUB..."
update-grub

echo "6e. Проверка существующих записей Ubuntu..."
UBUNTU_BOOTNUMS=$(efibootmgr | grep -i ubuntu | awk '{print $1}' | sed 's/Boot//;s/\*//')
if [ ! -z "$UBUNTU_BOOTNUMS" ]; then
    echo "Удаление старых записей Ubuntu..."
    for b in $UBUNTU_BOOTNUMS; do
        efibootmgr -b "$b" -B
    done
fi

echo "6f. Создание новой записи Ubuntu..."
efibootmgr -c -d /dev/nvme2n1 -p 1 -L "Ubuntu" -l '\EFI\ubuntu\shimx64.efi'

echo "6g. Проверка новой записи..."
efibootmgr -v

# Установим Ubuntu первым в BootOrder
NEW_NUM=$(efibootmgr | grep -i ubuntu | awk '{print $1}' | sed 's/Boot//;s/\*//')
WIN_NUM=$(efibootmgr | grep -i "Windows Boot Manager" | awk '{print $1}' | sed 's/Boot//;s/\*//')
if [ ! -z "$NEW_NUM" ]; then
    if [ ! -z "$WIN_NUM" ]; then
        efibootmgr -o $NEW_NUM,$WIN_NUM
    else
        efibootmgr -o $NEW_NUM
    fi
fi

echo "GRUB восстановлен! Выход из chroot..."
EOF

echo "7. Выход из Live USB и размонтирование..."
umount "$ROOT_MOUNT/dev"
umount "$ROOT_MOUNT/proc"
umount "$ROOT_MOUNT/sys"
umount "$EFI_MOUNT"
umount "$ROOT_MOUNT"

echo "✅ Восстановление UEFI GRUB завершено. Перезагружайтесь."
