#!/bin/bash

# Pi Zero W USB Mass Storage + SMB Setup Script
# This script configures a Raspberry Pi Zero W to act as both:
# 1. USB mass storage device (appears as thumb drive to connected device)
# 2. SMB network share (accessible over network with guest access)

set -e  # Exit on any error

echo "=== Raspberry Pi Zero W USB Mass Storage + SMB Setup ==="
echo "This will configure your Pi Zero W as a USB drive and network share"
echo

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "Please don't run this script as root. Run as regular user with sudo access."
   exit 1
fi

# Variables
USB_IMAGE_PATH="/home/$USER/usb_drive.img"
USB_IMAGE_SIZE="65536"  # Size in MB (64GB)
MOUNT_POINT="/mnt/usb_drive"

echo "Configuration:"
echo "- USB drive image: $USB_IMAGE_PATH"
echo "- USB drive size: ${USB_IMAGE_SIZE}MB (64GB)"
echo "- Mount point: $MOUNT_POINT"
echo "- SMB share name: USB_Drive"
echo "- SMB access: Guest (no password required)"
echo

read -p "Continue with setup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

echo
echo "=== Step 1: Configuring USB Gadget Mode ==="

# Backup original files
echo "Creating backups..."
sudo cp /boot/firmware/config.txt /boot/firmware/config.txt.backup
sudo cp /boot/firmware/cmdline.txt /boot/firmware/cmdline.txt.backup

# Add USB gadget overlay to config.txt if not already present
if ! grep -q "dtoverlay=dwc2" /boot/firmware/config.txt; then
    echo "Adding USB gadget overlay to config.txt..."
    echo "dtoverlay=dwc2" | sudo tee -a /boot/firmware/config.txt > /dev/null
else
    echo "USB gadget overlay already present in config.txt"
fi

# Modify cmdline.txt to load USB gadget modules
echo "Configuring cmdline.txt..."
CURRENT_CMDLINE=$(cat /boot/firmware/cmdline.txt)
if [[ ! "$CURRENT_CMDLINE" =~ "modules-load=dwc2,g_mass_storage" ]]; then
    # Insert modules-load after rootwait
    NEW_CMDLINE=$(echo "$CURRENT_CMDLINE" | sed 's/rootwait/rootwait modules-load=dwc2,g_mass_storage/')
    echo "$NEW_CMDLINE" | sudo tee /boot/firmware/cmdline.txt > /dev/null
    echo "Added USB gadget modules to cmdline.txt"
else
    echo "USB gadget modules already configured in cmdline.txt"
fi

echo
echo "=== Step 2: Creating USB Drive Image ==="

if [ ! -f "$USB_IMAGE_PATH" ]; then
    echo "Creating ${USB_IMAGE_SIZE}MB (64GB) drive image..."
    echo "This will take several minutes..."
    sudo dd if=/dev/zero of="$USB_IMAGE_PATH" bs=1M count="$USB_IMAGE_SIZE" status=progress
    
    echo "Formatting as FAT32..."
    sudo mkfs.vfat "$USB_IMAGE_PATH"
    
    echo "Setting ownership..."
    sudo chown "$USER:$USER" "$USB_IMAGE_PATH"
else
    echo "USB drive image already exists at $USB_IMAGE_PATH"
fi

# Create mount point
echo "Creating mount point..."
sudo mkdir -p "$MOUNT_POINT"

echo
echo "=== Step 3: Setting up Auto-Mount ==="

# Create mount script with proper permissions for SMB
echo "Creating auto-mount script..."
sudo tee /usr/local/bin/mount-usb-drive.sh > /dev/null << EOF
#!/bin/bash
# Auto-mount USB drive image with proper permissions for SMB
if [ -f "$USB_IMAGE_PATH" ] && ! mountpoint -q "$MOUNT_POINT"; then
    mount -o loop,umask=000,fmask=111,dmask=000 "$USB_IMAGE_PATH" "$MOUNT_POINT"
fi
EOF

sudo chmod +x /usr/local/bin/mount-usb-drive.sh

# Create systemd service for auto-mount instead of cron
echo "Creating auto-mount systemd service..."
sudo tee /etc/systemd/system/usb-mount.service > /dev/null << EOF
[Unit]
Description=Mount USB Drive Image
After=local-fs.target
Wants=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/mount-usb-drive.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the mount service
sudo systemctl enable usb-mount.service

echo
echo "=== Step 4: Setting up USB Gadget Service ==="

# Create improved USB gadget script with better error handling
echo "Creating USB gadget script..."
sudo tee /usr/local/bin/usb-gadget.sh > /dev/null << EOF
#!/bin/bash
# Wait for mount to be ready
sleep 5

# Check if image file exists and is mounted
if [ ! -f "$USB_IMAGE_PATH" ]; then
    echo "USB image file not found"
    exit 1
fi

if ! mountpoint -q "$MOUNT_POINT"; then
    echo "USB drive not mounted, attempting mount"
    mount -o loop,umask=000,fmask=111,dmask=000 "$USB_IMAGE_PATH" "$MOUNT_POINT"
    sleep 2
fi

# Remove module if already loaded
modprobe -r g_mass_storage 2>/dev/null || true

# Load with explicit parameters and error checking
modprobe g_mass_storage file=$USB_IMAGE_PATH removable=1 ro=0 stall=0

# Verify it loaded
if lsmod | grep -q g_mass_storage; then
    echo "USB mass storage gadget loaded successfully"
    exit 0
else
    echo "Failed to load USB mass storage gadget"
    exit 1
fi
EOF

sudo chmod +x /usr/local/bin/usb-gadget.sh

# Create systemd service with proper dependencies
echo "Creating USB gadget service..."
sudo tee /etc/systemd/system/usb-gadget.service > /dev/null << EOF
[Unit]
Description=USB Mass Storage Gadget
After=usb-mount.service
Requires=usb-mount.service
Wants=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/usb-gadget.sh
RemainAfterExit=yes
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
sudo systemctl enable usb-gadget.service

echo
echo "=== Step 5: Installing and Configuring SMB ==="

# Install Samba
echo "Installing Samba..."
sudo apt update
sudo apt install -y samba samba-common-bin

# Backup original Samba config
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.backup

# Configure Samba with guest access (simplified working config)
echo "Configuring SMB share with guest access..."
sudo tee -a /etc/samba/smb.conf > /dev/null << EOF

[USB_Drive]
   comment = Public USB Drive
   path = $MOUNT_POINT
   browseable = yes
   writable = yes
   guest ok = yes
   public = yes
   create mask = 0777
   directory mask = 0777
EOF

# Restart and enable Samba
echo "Starting Samba services..."
sudo systemctl restart smbd
sudo systemctl enable smbd
sudo systemctl restart nmbd
sudo systemctl enable nmbd

echo
echo "=== Step 6: Initial Mount and Test Files ==="

# Mount now for SMB setup
echo "Mounting USB drive image with proper permissions..."
sudo umount "$MOUNT_POINT" 2>/dev/null || true
sudo mount -o loop,umask=000,fmask=111,dmask=000 "$USB_IMAGE_PATH" "$MOUNT_POINT"

# Create test files
echo "Creating test files in the USB drive..."
echo "USB Drive created on $(date)" > "$MOUNT_POINT/README.txt"
mkdir -p "$MOUNT_POINT/gcode"
echo "Place your .gcode files here" > "$MOUNT_POINT/gcode/README.txt"

# Reload and start services
echo "Reloading systemd services..."
sudo systemctl daemon-reload
sudo systemctl start usb-mount.service
sudo systemctl start usb-gadget.service

echo
echo "=== Setup Complete! ==="
echo
echo "Configuration Summary:"
echo "- USB drive image: $USB_IMAGE_PATH (${USB_IMAGE_SIZE}MB / 64GB)"
echo "- Mount point: $MOUNT_POINT"
echo "- SMB share: //$(hostname -I | awk '{print $1}')/USB_Drive"
echo "- Web refresh interface: http://$(hostname -I | awk '{print $1}'):5000"
echo "- SMB access: Guest (no authentication required)"
echo
echo "Usage:"
echo "1. Upload files via SMB: //$(hostname -I | awk '{print $1}')/USB_Drive"
echo "2. Refresh USB via web: http://$(hostname -I | awk '{print $1}'):5000"
echo "3. Connect Pi to 3D printer via USB data port"
echo
echo "Or use SSH refresh command:"
echo "ssh $USER@$(hostname -I | awk '{print $1}') \"sudo umount -l /mnt/usb_drive && sudo mount -o loop,umask=000,fmask=111,dmask=000 $USB_IMAGE_PATH /mnt/usb_drive && sudo modprobe -r g_mass_storage && sleep 1 && sudo modprobe g_mass_storage file=$USB_IMAGE_PATH removable=1 ro=0 stall=0\""
echo
echo "The Pi will appear as a USB drive to your 3D printer and"
echo "you can manage files over the network with full read/write access."
echo
echo "Backup files created:"
echo "- /boot/firmware/config.txt.backup"
echo "- /boot/firmware/cmdline.txt.backup"
echo "- /etc/samba/smb.conf.backup"

read -p "Reboot now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Rebooting..."
    sudo reboot
else
    echo "Remember to reboot before testing: sudo reboot"
fi
