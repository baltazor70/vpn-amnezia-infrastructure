import subprocess, time, os, psutil
from functools import wraps
from flask import Flask, render_template, jsonify, request, session

app = Flask(__name__)
app.secret_key = os.urandom(24)
ADMIN_PASSWORD = os.environ.get("FLASK_ADMIN_PASSWORD", "vpn2026admin")

def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('authenticated'):
            return jsonify({'error': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return decorated

def get_ping(host):
    try:
        res = subprocess.run(['ping', '-c', '1', '-W', '2', host],
                             capture_output=True, text=True, timeout=3)
        for line in res.stdout.splitlines():
            if 'time=' in line:
                return line.split('time=')[1].split()[0] + ' ms'
    except:
        pass
    return 'N/A'

def check_vpn_service():
    try:
        res = subprocess.run(['docker', 'ps', '--filter', 'name=amnezia-awg2', '--format', '{{.Names}}'],
                             capture_output=True, text=True, timeout=5)
        return 'amnezia-awg2' in res.stdout
    except:
        return False

def read_metrics(file_name):
    try:
        with open(f'/var/log/vpn-metrics/{file_name}', 'r') as f:
            lines = f.readlines()
        data = []
        for line in lines:
            parts = line.strip().split()
            if len(parts) >= 8:
                data.append({
                    'time': parts[0],
                    'cpu': float(parts[1].replace('%', '')),
                    'ram': float(parts[2].replace('%', '')),
                    'disk': float(parts[3].replace('%', '')),
                    'rx': float(parts[4]) if parts[4] != '0' else 0,
                    'tx': float(parts[6]) if parts[6] != '0' else 0
                })
        return data
    except:
        return []

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/login', methods=['POST'])
def login():
    if request.json.get('password') == ADMIN_PASSWORD:
        session['authenticated'] = True
        return jsonify({'success': True})
    return jsonify({'success': False}), 401

@app.route('/logout', methods=['POST'])
def logout():
    session.clear()
    return jsonify({'success': True})

@app.route('/api/status')
@require_auth
def api_status():
    return jsonify({
        'server': 'online',
        'vpn_service': check_vpn_service(),
        'cpu': psutil.cpu_percent(),
        'ram_used': round(psutil.virtual_memory().used / (1024**2)),
        'ram_total': round(psutil.virtual_memory().total / (1024**2)),
        'disk': psutil.disk_usage('/').percent,
        'ping_1111': get_ping('1.1.1.1'),
        'ping_msk': get_ping('ya.ru'),
        'metrics': read_metrics('cpu.log'),
        'timestamp': time.strftime('%H:%M:%S')
    })

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
