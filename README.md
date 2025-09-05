# Pi Zero USB Storage Bridge

Most 3D printers only accept files from USB drives or SD cards. This means you have to physically walk to your printer, unplug the USB drive, copy files to it on your computer, then walk back and plug it in again. This gets annoying quickly when you're printing multiple files or making frequent changes.

The Raspberry Pi Zero W has built-in USB gadget functionality that lets it pretend to be a USB mass storage device. Combined with SMB file sharing, this means your 3D printer sees a regular USB drive while you can upload files over your network.

## How it works

1. Pi Zero W connects to your 3D printer's USB port
2. 3D printer sees it as a regular 64GB USB drive
3. You can access the same storage from any computer on your network
4. Upload gcode files remotely, printer reads them locally

## Requirements

- Raspberry Pi Zero W with Raspberry Pi OS installed
- MicroSD card (128GB recommended for 64GB virtual drive)
- USB data cable to connect to 3D printer
- Network connection (WiFi configured on Pi Zero W)

## Setup

1. SSH into your Pi Zero W or use the terminal directly
2. Download and run the setup script:
   ```bash
   wget https://raw.githubusercontent.com/christophacham/Pi-Zero-USB-Storage-Bridge/main/setup_usb_smb.sh
   chmod +x setup_usb_smb.sh
   ./setup_usb_smb.sh
   ```
3. The script will:
   - Create a 64GB virtual USB drive (takes about 60-90 minutes)
   - Configure USB gadget mode
   - Set up SMB sharing with guest access
   - Create systemd services for auto-start
4. Reboot when prompted
5. Connect Pi to your 3D printer using the USB data port (not power port)

## Access files

From any computer on your network:
- Windows: `\\[Pi-IP-Address]\USB_Drive`
- Mac/Linux: `smb://[Pi-IP-Address]/USB_Drive`

No password required. Just copy your gcode files and they'll be available to your 3D printer immediately.

## Important gotchas and troubleshooting

### Physical connection
- Use the USB data port on Pi Zero W (labeled "USB"), not the power port ("PWR")
- Must use a data cable, not a power-only cable
- Some USB cables are charge-only and won't work

### After reboot issues
If the Pi doesn't appear as a USB drive after reboot:
```bash
# Check if services are running
sudo systemctl status usb-mount.service
sudo systemctl status usb-gadget.service

# If not working, restart the USB gadget
sudo modprobe -r g_mass_storage
sudo modprobe g_mass_storage file=/home/[username]/usb_drive.img removable=1 ro=0 stall=0
```

### Network access problems
If you can't write to the network share:
```bash
# Check if drive is mounted with correct permissions
mount | grep usb_drive
# Should show: umask=000,fmask=111,dmask=000

# If not, remount:
sudo umount /mnt/usb_drive
sudo mount -o loop,umask=000,fmask=111,dmask=000 /home/[username]/usb_drive.img /mnt/usb_drive
```

### File access conflicts
- Don't access files over network while 3D printer is reading from the drive
- Always safely eject from Windows before connecting to printer
- If printer shows corrupted files, reboot the Pi to reset the USB connection

### SD card space
- The script creates a 64GB file that takes up actual space on your SD card
- Make sure you have at least 70GB free space before running
- Monitor disk usage with `df -h`

## What the script does

- Enables USB gadget mode in Pi OS boot configuration
- Creates a 64GB virtual USB drive (FAT32 format) 
- Sets up SMB sharing with guest access (no authentication)
- Creates systemd services for reliable auto-start on boot
- Configures proper mount permissions for network write access

## Performance notes

- Transfer speeds limited by USB 2.0 (Pi Zero W) and SD card speed
- Large gcode files may take time to transfer over network
- USB connection to printer is faster than network transfer
- Use a high-quality SD card (Class 10 or better) for best performance

That's it. No more walking back and forth to swap USB drives.
