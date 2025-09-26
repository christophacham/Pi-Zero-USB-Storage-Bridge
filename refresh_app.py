from flask import Flask
import subprocess
import os

app = Flask(__name__)

@app.route('/')
def home():
    return '''
    <html>
    <body>
        <h2>Pi USB Refresh</h2>
        <form action="/refresh" method="post">
            <button type="submit" style="font-size:20px; padding:10px;">Refresh USB Drive</button>
        </form>
    </body>
    </html>
    '''

@app.route('/refresh', methods=['POST'])
def refresh():
    try:
        subprocess.run(['sudo', 'umount', '/mnt/usb_drive'], check=False)
        subprocess.run(['sudo', 'mount', '-o', 'loop,umask=000,fmask=111,dmask=000', '/home/bob/usb_drive.img', '/mnt/usb_drive'], check=True)
        subprocess.run(['sudo', 'modprobe', '-r', 'g_mass_storage'], check=False)
        subprocess.run(['sleep', '1'], check=True)
        subprocess.run(['sudo', 'modprobe', 'g_mass_storage', 'file=/home/bob/usb_drive.img', 'removable=1', 'ro=0', 'stall=0'], check=True)
        return '<h2>USB refreshed successfully!</h2><a href="/">Back</a>'
    except Exception as e:
        return f'<h2>Error: {e}</h2><a href="/">Back</a>'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
