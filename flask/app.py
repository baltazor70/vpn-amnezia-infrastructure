import subprocess, time, os, psutil, json, urllib.request
from functools import wraps
from flask import Flask, render_template, jsonify, request, session

app = Flask(__name__)
app.secret_key = os.urandom(24)
ADMIN_PASSWORD = os.environ.get("FLASK_ADMIN_PASSWORD", "vpn2026admin")
_info_cache, _ict = {}, 0
_geo_cache = {}

def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('authenticated'): return jsonify({'error': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return decorated

def get_client_info():
    global _info_cache, _ict
    if time.time() - _ict < 30: return _info_cache
    info = {}
    try:
        out = subprocess.run(['docker','exec','amnezia-awg2','cat','/opt/amnezia/awg/clientsTable'], capture_output=True, text=True, timeout=3).stdout
        data = json.loads(out)
        clients = data if isinstance(data, list) else (data.values() if isinstance(data, dict) else [])
        for c in clients:
            ud = c.get("userData", c)
            name = ud.get("clientName", "").strip()
            c_date = ud.get("creationDate") or ud.get("creation_date", "Неизвестно")
            raw_ip = str(ud.get("allowedIps", ud.get("allowed_ips", ""))).strip().replace('"','')
            ip = raw_ip.split("/")[0].strip()
            pubkey = c.get("clientId", "").strip()
            if ip and name: info[ip] = {"name": name, "creation_date": c_date}
            if pubkey and name: info[pubkey] = {"name": name, "creation_date": c_date}
    except Exception as e:
        print(f" clientsTable error: {e}")
    _info_cache, _ict = info, time.time()
    return info

def parse_wg_data():
    try:
        res = subprocess.run(['docker', 'exec', 'amnezia-awg2', 'wg', 'show'], capture_output=True, text=True, timeout=5)
        if res.returncode != 0: return []
        
        peers = []
        cur = {}
        for line in res.stdout.splitlines():
            line = line.strip()
            if line.startswith('peer:'):
                if cur.get('allowed_ip') and cur.get('allowed_ip') != '-': peers.append(cur)
                cur = {'full_key': line.split('peer:')[1].strip(), 'endpoint':'-', 'allowed_ip':'-', 'handshake':'-', 'rx':'0 B', 'tx':'0 B'}
            elif line.startswith('endpoint:'): cur['endpoint'] = line.split('endpoint:')[1].strip()
            elif line.startswith('allowed ips:'): cur['allowed_ip'] = line.split('allowed ips:')[1].strip().split('/')[0]
            elif line.startswith('latest handshake:'): cur['handshake'] = line.split('latest handshake:')[1].strip()
            elif line.startswith('transfer:'):
                parts = line.split('transfer:')[1].strip().split(', ')
                if len(parts) == 2:
                    cur['tx'] = parts[0].replace(' received', '').strip()
                    cur['rx'] = parts[1].replace(' sent', '').strip()
        if cur.get('allowed_ip') and cur.get('allowed_ip') != '-': peers.append(cur)
        
        cinfo = get_client_info()
        fetched = 0
        
        for p in peers:
            ext_ip = p['endpoint'].split(':')[0] if p['endpoint'] != '-' else ''
            p['ext_ip'] = ext_ip
            
            key_ip = p['allowed_ip'].strip().replace('"','')
            key_pub = p['full_key'].strip().replace('"','')
            
            info = cinfo.get(key_ip)
            if not info: info = cinfo.get(key_pub)
            
            p['display_name'] = info.get('name', f"IP {key_ip}") if info else f"IP {key_ip}"
            p['creation_date'] = info.get('creation_date', 'Неизвестно') if info else 'Неизвестно'
            
            # ГЕОЛОКАЦИЯ
            if ext_ip and '.' in ext_ip:
                if ext_ip not in _geo_cache:
                    try:
                        url = f"http://ip-api.com/json/{ext_ip}?fields=status,lat,lon,city,regionName,isp"
                        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
                        with urllib.request.urlopen(req, timeout=3) as r:
                            d = json.loads(r.read().decode())
                            if d.get('status') == 'success':
                                _geo_cache[ext_ip] = {
                                    'lat': d['lat'], 'lon': d['lon'], 
                                    'city': d.get('city',''), 'region': d.get('regionName',''), 
                                    'isp': d.get('isp','')
                                }
                                fetched += 1
                            else:
                                _geo_cache[ext_ip] = None
                    except Exception as e:
                        print(f"Geo fail {ext_ip}: {e}")
                        _geo_cache[ext_ip] = None
                    time.sleep(0.2) # Задержка чтобы не забанили
                
                p['geo'] = _geo_cache.get(ext_ip)
                p['isp'] = _geo_cache.get(ext_ip, {}).get('isp', '-') if _geo_cache.get(ext_ip) else '-'
            else:
                p['geo'] = None
                p['isp'] = '-'
        return peers
    except Exception as e:
        print(f"Parse error: {e}")
        return []

# ... остальные роуты без изменений ...
def get_ping(host):
    try:
        for l in subprocess.run(['ping','-c','1','-W','2',host], capture_output=True, text=True, timeout=2).stdout.splitlines():
            if 'time=' in l: return l.split('time=')[1].split()[0]+' ms'
    except: return 'N/A'

def check_vpn():
    try: return 'amnezia-awg2' in subprocess.run(['docker','ps','--filter','name=amnezia-awg2','--format','{{.Names}}'], capture_output=True, text=True, timeout=3).stdout
    except: return False

def active_users():
    try:
        out = subprocess.run(['docker','exec','amnezia-awg2','wg','show'], capture_output=True, text=True, timeout=3).stdout
        count = 0
        for l in out.splitlines():
            if 'latest handshake:' in l:
                hs = l.split('latest handshake:')[1].strip().lower()
                if 'second' in hs: count += 1
                elif 'minute' in hs and 'hour' not in hs and 'day' not in hs: count += 1
        return count
    except: return 0

def read_metrics(fn):
    try:
        with open(f'/var/log/vpn-metrics/{fn}') as f: lines = f.readlines()
        return [{'time':p[0],'cpu':float(p[1].replace('%','')),'ram':float(p[2].replace('%','')),'disk':float(p[3].replace('%','')),'rx':float(p[4]) if p[4]!='0' else 0,'tx':float(p[6]) if p[6]!='0' else 0} for l in lines if (p:=l.strip().split()) and len(p)>=8]
    except: return []

def f2b_dash():
    stats = {'sshd':{'c':0,'t':0}, 'vpn-monitoring':{'c':0,'t':0}}
    for j in stats:
        try:
            for l in subprocess.run(['fail2ban-client','status',j], capture_output=True, text=True, check=True, timeout=2).stdout.split('\n'):
                if 'Currently banned:' in l: stats[j]['c']=int(l.split(':')[1].strip())
                elif 'Total banned:' in l: stats[j]['t']=int(l.split(':')[1].strip())
        except: pass
    return {k:{'current':v['c'],'total':v['t']} for k,v in stats.items()}

@app.route('/')
def index(): return render_template('index.html', f2b_stats=f2b_dash())
@app.route('/login', methods=['POST'])
def login():
    if request.json.get('password') == ADMIN_PASSWORD: session['authenticated']=True; return jsonify({'success':True})
    return jsonify({'success':False}), 401
@app.route('/logout', methods=['POST'])
def logout(): session.clear(); return jsonify({'success':True})
@app.route('/api/status')
@require_auth
def api_status():
    return jsonify({'server':'online','vpn_service':check_vpn(),'cpu':psutil.cpu_percent(),'ram_used':round(psutil.virtual_memory().used/(1024**2)),'ram_total':round(psutil.virtual_memory().total/(1024**2)),'disk':psutil.disk_usage('/').percent,'ping_1111':get_ping('1.1.1.1'),'ping_msk':get_ping('ya.ru'),'active_users':active_users(),'metrics':read_metrics('cpu.log'),'timestamp':time.strftime('%H:%M:%S')})
@app.route('/api/fail2ban')
@require_auth
def api_f2b(): return jsonify(f2b_dash())
@app.route('/api/admin/peers')
@require_auth
def get_peers(): return jsonify({'status':'ok', 'peers': parse_wg_data()})
@app.route('/api/load_map')
@require_auth
def load_map():
    peers = parse_wg_data()
    active = sum(1 for p in peers if 'second' in p.get('handshake','').lower() or ('minute' in p.get('handshake','').lower() and 'hour' not in p.get('handshake','').lower()))
    def parse_t(s):
        if not s or s == '0 B': return 0
        n = float(''.join(c for c in str(s) if c.isdigit() or c == '.'))
        if 'GiB' in s: return n * 1024
        if 'MiB' in s: return n
        return n
    total_gb = sum(parse_t(p['rx']) + parse_t(p['tx']) for p in peers) / 1024
    geo_count = sum(1 for p in peers if p.get('geo'))
    # Отладочный вывод в консоль сервера
    print(f"Map Request: {len(peers)} peers, {geo_count} geo OK")
    return jsonify({'status': 'ok', 'peers': peers, 'active': active, 'fetched_geo': geo_count, 'total_peers': len(peers), 'total_gb': round(total_gb, 2)})
@app.route('/map')
@require_auth
def map_page(): return render_template('map.html')

if __name__ == '__main__': app.run(host='127.0.0.1', port=8080)
