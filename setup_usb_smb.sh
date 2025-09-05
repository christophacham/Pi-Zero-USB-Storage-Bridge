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
echo "- USB drive size: ${USB_IMAGE_SIZE}MB"
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
    echo "Creating ${USB_IMAGE_SIZE}MB drive image..."
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
echo "=== Step 3: Setting up USB Gadget Service ==="

# Create USB gadget script
echo "Creating USB gadget script..."
sudo tee /usr/local/bin/usb-gadget.sh > /dev/null << EOF
#!/bin/bash
# Load USB mass storage gadget module
modprobe g_mass_storage file=$USB_IMAGE_PATH removable=1
EOF

sudo chmod +x /usr/local/bin/usb-gadget.sh

# Create systemd service
echo "Creating USB gadget service..."
sudo tee /etc/systemd/system/usb-gadget.service > /dev/null << EOF
[Unit]
Description=USB Mass Storage Gadget
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/usb-gadget.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
sudo systemctl enable usb-gadget.service

echo
echo "=== Step 4: Setting up Auto-Mount ==="

# Create mount script
echo "Creating auto-mount script..."
sudo tee /usr/local/bin/mount-usb-drive.sh > /dev/null << EOF
#!/bin/bash
# Auto-mount USB drive image
if [ -f "$USB_IMAGE_PATH" ] && ! mountpoint -q "$MOUNT_POINT"; then
    mount -o loop "$USB_IMAGE_PATH" "$MOUNT_POINT"
    chown $USER:$USER "$MOUNT_POINT"
    chmod 755 "$MOUNT_POINT"
fi
EOF

sudo chmod +x /usr/local/bin/mount-usb-drive.sh

# Add to crontab for auto-mount at boot
echo "Setting up auto-mount at boot..."
(sudo crontab -l 2>/dev/null; echo "@reboot /usr/local/bin/mount-usb-drive.sh") | sudo crontab -

# Mount now for SMB setup
echo "Mounting USB drive image..."
sudo /usr/local/bin/mount-usb-drive.sh

echo
echo "=== Step 5: Installing and Configuring SMB ==="

# Install Samba
echo "Installing Samba..."
sudo apt update
sudo apt install -y samba samba-common-bin

# Backup original Samba config
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.backup

# Configure Samba with guest access
echo "Configuring SMB share with guest access..."
sudo tee -a /etc/samba/smb.conf > /dev/null << EOF

[USB_Drive]
comment = USB Drive Share
path = $MOUNT_POINT
browseable = yes
writable = yes
guest ok = yes
read only = no
create mask = 0777
directory mask = 0777
force user = $USER
force group = $USER
public = yes
EOF

# Restart and enable Samba
echo "Starting Samba services..."
sudo systemctl restart smbd
sudo systemctl enable smbd
sudo systemctl restart nmbd
sudo systemctl enable nmbd

echo
echo "=== Step 6: Creating Test Files ==="

# Create a test file
echo "Creating test files in the USB drive..."
echo "USB Drive created on $(date)" | sudo tee "$MOUNT_POINT/README.txt" > /dev/null
sudo mkdir -p "$MOUNT_POINT/gcode"
echo "Place your .gcode files here" | sudo tee "$MOUNT_POINT/gcode/README.txt" > /dev/null

# Fix permissions
sudo chown -R "$USER:$USER" "$MOUNT_POINT"
sudo chmod -R 755 "$MOUNT_POINT"

echo
echo "=== Setup Complete! ==="
echo
echo "Configuration Summary:"
echo "- USB drive image: $USB_IMAGE_PATH (${USB_IMAGE_SIZE}MB / 64GB)"
echo "- Mount point: $MOUNT_POINT"
echo "- SMB share: //$(hostname -I | awk '{print $1}')/USB_Drive"
echo "- SMB access: Guest (no authentication required)"
echo
echo "Next Steps:"
echo "1. Reboot your Pi: sudo reboot"
echo "2. Connect Pi Zero W to your 3D printer via USB data port"
echo "3. Access files via network: //$(hostname -I | awk '{print $1}')/USB_Drive"
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
