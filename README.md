# Pi Zero USB Storage Bridge

Most 3D printers only accept files from USB drives or SD cards. This means you have to physically walk to your printer, unplug the USB drive, copy files to it on your computer, then walk back and plug it in again. This gets annoying quickly when you're printing multiple files or making frequent changes.

The Raspberry Pi Zero W has built-in USB gadget functionality that lets it pretend to be a USB mass storage device. Combined with SMB file sharing, this means your 3D printer sees a regular USB drive while you can upload files over your network.

## How it works

1. Pi Zero W connects to your 3D printer's USB port
2. 3D printer sees it as a regular 64GB USB drive
3. You can access the same storage from any computer on your network
4. Upload gcode files remotely, printer reads them locally

## Requirements

- Raspberry Pi Zero W
- MicroSD card (128GB recommended for 64GB virtual drive)
- USB data cable to connect to 3D printer

## Setup

1. SSH into your Pi Zero W
2. Download and run the setup script:
   ```bash
   wget https://raw.githubusercontent.com/yourusername/pi-zero-usb-storage-bridge/main/setup_usb_smb.sh
   chmod +x setup_usb_smb.sh
   ./setup_usb_smb.sh
   ```
3. Reboot when prompted
4. Connect Pi to your 3D printer using the USB data port (not power port)

## Access files

From any computer on your network:
- Windows: `\\[Pi-IP-Address]\USB_Drive`
- Mac/Linux: `smb://[Pi-IP-Address]/USB_Drive`

No password required. Just copy your gcode files and they'll be available to your 3D printer immediately.

## What the script does

- Enables USB gadget mode in Pi OS
- Creates a 64GB virtual USB drive (FAT32 format)
- Sets up SMB sharing with guest access
- Configures everything to start automatically on boot

That's it. No more walking back and forth to swap USB drives.
