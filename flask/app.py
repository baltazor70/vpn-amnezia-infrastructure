import subprocess, time, os, psutil, json, urllib.request
from functools import wraps
from flask import Flask, render_template, jsonify, request, session

app = Flask(__name__)
app.secret_key = os.urandom(24)
ADMIN_PASSWORD = os.environ.get("FLASK_ADMIN_PASSWORD", "vpn2026admin")
_names_cache, _isp_cache = {}, {}
_cache_time, _isp_cache_time = 0, 0

def require_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get('authenticated'): return jsonify({'error': 'Unauthorized'}), 401
        return f(*args, **kwargs)
    return decorated

def get_names_map():
    global _names_cache, _cache_time
    if time.time() - _cache_time < 60: return _names_cache
    names = {}
    try:
        with open('/root/ip_names.txt') as f:
            for l in f:
                if not l.startswith('#') and l.strip():
                    p = l.strip().split(maxsplit=1)
                    if len(p)==2: names[p[0]] = p[1]
    except: pass
    try:
        out = subprocess.run(['docker','exec','amnezia-awg2','cat','/opt/amnezia/awg/clientsTable'], capture_output=True, text=True, timeout=5).stdout
        data = json.loads(out)
        clients = data if isinstance(data, list) else (data.values() if isinstance(data, dict) else [])
        for c in clients:
            ud = c.get("userData", {})
            name = ud.get("clientName", "")
            raw_ip = str(ud.get("allowedIps", ud.get("allowed_ips", "")))
            if raw_ip and name and "/" in raw_ip: names[raw_ip.split("/")[0]] = name
            if c.get("clientId") and name: names[c["clientId"]] = name
    except: pass
    _names_cache, _cache_time = names, time.time()
    return names

def get_isp_info(ip):
    global _isp_cache, _isp_cache_time
    if time.time() - _isp_cache_time > 86400: _isp_cache.clear(); _isp_cache_time = time.time()
    if ip in _isp_cache: return _isp_cache[ip]
    if ip in ('-', '', '0.0.0.0'): _isp_cache[ip] = '-'; return '-'
    try:
        req = urllib.request.Request(f"http://ip-api.com/json/{ip}?fields=isp,org", headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=2) as r:
            data = json.loads(r.read().decode())
            isp = data.get('isp') or data.get('org') or 'Unknown'
            _isp_cache[ip] = isp
            return isp
    except:
        _isp_cache[ip] = '-'
        return '-'

def get_ping(host):
    try:
        for l in subprocess.run(['ping','-c','1','-W','2',host], capture_output=True, text=True, timeout=3).stdout.splitlines():
            if 'time=' in l: return l.split('time=')[1].split()[0]+' ms'
    except: pass
    return 'N/A'

def check_vpn():
    try: return 'amnezia-awg2' in subprocess.run(['docker','ps','--filter','name=amnezia-awg2','--format','{{.Names}}'], capture_output=True, text=True, timeout=5).stdout
    except: return False

def active_users():
    try:
        out = subprocess.run(['docker','exec','amnezia-awg2','wg','show'], capture_output=True, text=True, timeout=5).stdout
        return sum(1 for l in out.splitlines() if 'latest handshake:' in l and ('second' in l or ('minute' in l and '2 minute' not in l)))
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
            for l in subprocess.run(['fail2ban-client','status',j], capture_output=True, text=True, check=True, timeout=3).stdout.split('\n'):
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
@app.route('/test')
def test_page(): return 'OK'
@app.route('/api/fail2ban')
def api_f2b(): return jsonify(f2b_dash())

@app.route('/api/admin/peers')
@require_auth
def get_peers():
    try:
        names = get_names_map()
        res = subprocess.run(['docker','exec','amnezia-awg2','wg','show'], capture_output=True, text=True, timeout=5)
        if res.returncode != 0: return jsonify({'status':'error'}), 500
        peers, cur = [], {}
        for line in res.stdout.splitlines():
            line = line.strip()
            if line.startswith('peer:'):
                if cur:
                    cur['display_name'] = names.get(cur['allowed_ip'], names.get(cur['full_key'], cur['allowed_ip']))
                    peers.append(cur)
                cur = {'full_key': line.split('peer:')[1].strip(), 'endpoint':'-', 'allowed_ip':'-', 'handshake':'-', 'rx':'0 B', 'tx':'0 B'}
            elif line.startswith('endpoint:') and cur: cur['endpoint'] = line.split('endpoint:')[1].strip()
            elif line.startswith('allowed ips:') and cur: cur['allowed_ip'] = line.split('allowed ips:')[1].strip().split('/')[0]
            elif line.startswith('latest handshake:') and cur: cur['handshake'] = line.split('latest handshake:')[1].strip()
            elif line.startswith('transfer:') and cur:
                raw = line.split('transfer:')[1].strip().split(', ')
                #  МЕНЯЕМ ПЕРСПЕКТИВУ: RX = Клиент скачал (Server Sent), TX = Клиент загрузил (Server Received)
                cur['rx'], cur['tx'] = raw[1].replace(' sent',''), raw[0].replace(' received','')
        if cur:
            cur['display_name'] = names.get(cur['allowed_ip'], names.get(cur['full_key'], cur['allowed_ip']))
            peers.append(cur)
        
        # Добавляем ISP к каждому пиру
        for p in peers:
            p['isp'] = get_isp_info(p['endpoint'].split(':')[0] if p['endpoint'] != '-' else '-')
            p['pubkey'] = p.pop('full_key','')[:8]+'...'
            
        return jsonify({'status':'ok', 'peers':peers})
    except Exception as e: return jsonify({'status':'error', 'message':str(e)}), 500

if __name__ == '__main__': app.run(host='127.0.0.1', port=8080)
