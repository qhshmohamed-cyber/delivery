"""Bounded, authorized live QA. Requires disposable, isolated fixture accounts.

Never use a real employee manifest. This drives the public Auth/REST/Realtime
interfaces, not 200 rendered browser windows or 200 physical GPS devices.
Credentials and access tokens are never included in the evidence report.
Fixture cleanup is performed separately by the operator using exact QA tags.
"""
import asyncio, collections, datetime, json, pathlib, re, statistics, sys, time, uuid, os
import aiohttp

ROOT = pathlib.Path(__file__).resolve().parents[1]
html = (ROOT / 'index.html').read_text()
URL = re.search(r"const SB_URL = '([^']+)'", html)[1]
KEY = re.search(r"const SB_KEY = '([^']+)'", html)[1]
manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
OUT = pathlib.Path(sys.argv[2])
TARGET_USERS = len(manifest['accounts'])
TARGET_ORDERS = int(sys.argv[3]) if len(sys.argv)>3 else 100
BASELINE_ORDERS = int(sys.argv[4]) if len(sys.argv)>4 else 0
RESUME_ORDERS = json.loads(pathlib.Path(os.environ['TASK_QA_RESUME_ORDERS']).read_text()) if os.environ.get('TASK_QA_RESUME_ORDERS') else []
RESUME_BY_INDEX = {int(r['order_no'].rsplit('-',1)[1]):r for r in RESUME_ORDERS}
assert TARGET_USERS in (200,250,400)
assert TARGET_ORDERS in (100,500,1000)
assert all(a['email'].endswith('@example.invalid') and a['email'].startswith(manifest['tag']) for a in manifest['accounts'])
evidence = dict(tag=manifest['tag'], started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), requested_users=TARGET_USERS, requested_orders=TARGET_ORDERS,
                methodology='200 independent Auth/REST/Realtime clients; not browser rendering or physical GPS', stages=[], findings=[])
metrics = collections.defaultdict(list)
checks = collections.Counter()
events = collections.Counter()
connections, readers = [], []
receipts = {}
network_gate = asyncio.Semaphore(40)
request_clock = 0.0
request_lock = asyncio.Lock()
TOKEN_FILE = pathlib.Path(sys.argv[1]+'.tokens.json')
inflight = peak = 0

def save():
    OUT.write_text(json.dumps(evidence, ensure_ascii=False, indent=2))

def note(stage, **data):
    row = dict(stage=stage, **data)
    evidence['stages'].append(row)
    save()
    print(json.dumps(row, ensure_ascii=False), flush=True)

def verify(condition, label):
    checks[label] += 1
    if not condition:
        raise AssertionError(label)

async def request(session, actor, label, method, path, body=None, expected=(200, 201, 204)):
    global inflight, peak
    headers = {'apikey': KEY, 'Content-Type': 'application/json'}
    if actor and actor.get('token'):
        headers['Authorization'] = 'Bearer ' + actor['token']
    # A bounded realistic activity rate, not a flood of thousands of clicks.
    global request_clock
    async with request_lock:
        delay = max(0, request_clock-time.monotonic())
        request_clock = max(request_clock,time.monotonic()) + (1/20)
    await asyncio.sleep(delay)
    await network_gate.acquire()
    started = time.perf_counter()
    inflight += 1
    peak = max(peak, inflight)
    status, code = 0, None
    try:
        async with session.request(method, URL+path, headers=headers, json=body) as r:
            status = r.status
            raw = await r.text()
            try:
                value = json.loads(raw) if raw else None
            except ValueError:
                value = None
            if status not in expected:
                code = value.get('code') or value.get('error_code') if isinstance(value, dict) else None
                detail = str(value.get('message',''))[:180] if isinstance(value,dict) else raw[:180]
                if status == 429 and not label.startswith('auth_') and not label.endswith('_retry'):
                    await asyncio.sleep(3)
                    network_gate.release()
                    try:
                        return await request(session,actor,label+'_retry',method,path,body,expected)
                    finally:
                        await network_gate.acquire()
                raise RuntimeError(f'{label}: HTTP {status}, code={code}, detail={detail}')
            return value
    finally:
        inflight -= 1
        network_gate.release()
        metrics[label].append(dict(ms=round((time.perf_counter()-started)*1000, 2), status=status, code=code))

async def rpc(session, actor, name, args=None, expected=(200, 204), label=None):
    return await request(session, actor, label or name, 'POST', '/rest/v1/rpc/'+name, args or {}, expected)

async def login(session, actor):
    try:
        result = await request(session, None, 'auth_password', 'POST', '/auth/v1/token?grant_type=password',
                               {'email': actor['email'], 'password': actor['password']})
        verify(result['user']['id'] == actor['user_id'], 'login_identity')
        actor['token'] = result['access_token']
        return actor
    except Exception as e:
        
        if str(e) not in evidence['findings']:
            evidence['findings'].append(str(e))
        return None

async def read_socket(ws, actor, pending):
    try:
        async for msg in ws:
            if msg.type != aiohttp.WSMsgType.TEXT:
                continue
            j = json.loads(msg.data)
            events['frame:'+j.get('event','unknown')] += 1
            ref = j.get('ref')
            if j.get('event') == 'phx_reply' and ref in pending:
                if not pending[ref].done():
                    pending[ref].set_result(j.get('payload', {}))
            elif j.get('event') == 'postgres_changes':
                events['postgres_changes'] += 1
                data = j.get('payload', {}).get('data', {})
                record = data.get('record') or {}
                if data.get('table') == 'dlv_orders' and record:
                    if record.get('branch_id') != actor['branch_id']:
                        events['foreign_branch_leak'] += 1
                    if actor['job'] == 'driver' and record.get('driver_id') != actor['user_id']:
                        events['foreign_driver_leak'] += 1
            elif j.get('event') == 'broadcast' and j.get('payload', {}).get('event') == 'staff_message':
                events['staff_broadcast'] += 1
                mid = j.get('payload', {}).get('payload', {}).get('id')
                if mid:
                    receipts[mid] = time.perf_counter()
            elif j.get('event') in ('phx_error', 'phx_close'):
                events[j['event']] += 1
            elif j.get('event') == 'system':
                if j.get('payload', {}).get('status') == 'error':
                    events['system_error'] += 1
                    reason = str(j.get('payload', {}).get('message', ''))[:180]
                    if reason and reason not in evidence['findings']:
                        evidence['findings'].append(reason)
    except Exception as e:
        events['socket_reader_error'] += 1

async def phoenix_heartbeat(ws):
    while not ws.closed:
        await asyncio.sleep(20)
        if not ws.closed:
            await ws.send_json({'topic':'phoenix','event':'heartbeat','payload':{},'ref':str(uuid.uuid4())})

async def connect(session, actor, index):
    if index>=200:
        actor['channels']=0
        events['test_driver_polling_clients']+=1
        return 0
    await asyncio.sleep(index * 0.045)  # Respect the normal join-rate budget.
    pending = {}
    try:
        ws = await session.ws_connect(URL.replace('https://', 'wss://')+'/realtime/v1/websocket?apikey='+KEY+'&vsn=1.0.0', heartbeat=20, timeout=20)
        connections.append(ws)
        readers.append(asyncio.create_task(read_socket(ws, actor, pending)))
        readers.append(asyncio.create_task(phoenix_heartbeat(ws)))
        configs = [
            ('orders:user:'+actor['user_id'], [{'event': '*', 'schema': 'public', 'table': 'dlv_orders'}, {'event': 'INSERT', 'schema': 'public', 'table': 'dlv_incidents'}]),
            ('profile:user:'+actor['user_id'], [{'event': 'UPDATE', 'schema': 'public', 'table': 'dlv_profiles', 'filter': 'user_id=eq.'+actor['user_id']}]),
            ('brand:company:'+str(actor['company_id']), [{'event': 'UPDATE', 'schema': 'public', 'table': 'dlv_company_branding', 'filter': 'company_id=eq.'+str(actor['company_id'])}])]
        successful = 0
        for topic, changes in configs:
            ref = str(uuid.uuid4())
            future = asyncio.get_running_loop().create_future()
            pending[ref] = future
            await ws.send_json({'topic': 'realtime:'+topic, 'event': 'phx_join', 'ref': ref, 'join_ref': ref,
                                'payload': {'config': {'broadcast': {'ack': False, 'self': False}, 'presence': {'key': ''}, 'postgres_changes': changes, 'private': True}, 'access_token': actor['token']}})
            response = await asyncio.wait_for(future, 25)
            metrics['realtime_join'].append({'ms': 0, 'status': 200 if response.get('status') == 'ok' else 400})
            if response.get('status') == 'ok':
                successful += 1
            else:
                events['join_rejected'] += 1
                reason = str(response.get('response', {}))[:220]
                if reason not in evidence['findings']:
                    evidence['findings'].append(reason)
        actor['channels'] = successful
        return successful
    except Exception as e:
        events['connection_failed'] += 1
        reason='Realtime connected-user limit (HTTP 429)' if getattr(e,'status',None)==429 else 'Realtime: '+type(e).__name__
        if reason not in evidence['findings']:
            evidence['findings'].append(reason)
        return 0

async def snapshot(session, actor):
    await rpc(session, actor, 'dlv_team_ping', {'p_visible': True})
    rows = await request(session, actor, 'orders_read', 'GET', '/rest/v1/dlv_orders?select=id,branch_id,driver_id,status,workflow_stage&branch_id=eq.'+str(actor['branch_id'])+'&limit=500')
    verify(all(r['branch_id'] == actor['branch_id'] for r in rows), 'own_branch_read')
    if actor['job'] == 'driver':
        verify(all(r['driver_id'] == actor['user_id'] for r in rows), 'own_driver_read')
    await rpc(session, actor, 'dlv_team_inbox')

async def fallback_poll(session, actor):
    await asyncio.sleep(actor['idx'] % 30)
    while True:
        rows = await request(session,actor,'fallback_orders_poll','GET','/rest/v1/dlv_orders?select=id,branch_id,driver_id,status&branch_id=eq.'+str(actor['branch_id'])+'&limit=500')
        verify(all(r['branch_id']==actor['branch_id'] for r in rows),'fallback_branch_isolation')
        if actor['job']=='driver':
            verify(all(r['driver_id']==actor['user_id'] for r in rows),'fallback_driver_isolation')
        await asyncio.sleep(30)

async def main():
    actors = manifest['accounts']
    connector = aiohttp.TCPConnector(limit=300, limit_per_host=250)
    async with aiohttp.ClientSession(connector=connector, trust_env=True, timeout=aiohttp.ClientTimeout(total=40)) as session:
        try:
            cached = json.loads(TOKEN_FILE.read_text()) if TOKEN_FILE.exists() else []
            cached = {a['user_id']:a for a in cached}
            for actor in actors:
                previous = cached.get(actor['user_id'],{})
                if previous.get('token'):
                    actor['token'] = previous['token']
            async def paced_login(actor, i):
                if actor.get('token'):
                    return actor  # Disposable token just exercised in the previous stage; boot RPCs revalidate it.
                await asyncio.sleep(max(0,i-19) * 2.1)
                result = await login(session, actor)
                if result is None:
                    await asyncio.sleep(5)
                    result = await login(session, actor)
                if (i+1) % 20 == 0:
                    note('login_progress', launched=i+1, authenticated=sum(bool(a.get('token')) for a in actors))
                return result
            new_index = 0
            login_tasks = []
            for actor in actors:
                login_tasks.append(paced_login(actor, new_index))
                if not actor.get('token'):
                    new_index += 1
            logged = await asyncio.gather(*login_tasks)
            actors = [a for a in logged if a]
            TOKEN_FILE.write_text(json.dumps(actors));os.chmod(TOKEN_FILE,0o600)
            note('login', successful=len(actors), requested=TARGET_USERS)
            if len(actors) != TARGET_USERS:
                raise RuntimeError('Not all requested accounts authenticated; no operational success claim')
            joins = await asyncio.gather(*(connect(session, a, i) for i, a in enumerate(actors)))
            note('realtime', socket_connections=len(connections), live_connections=sum(not ws.closed for ws in connections), test_driver_realtime_cap=200, all_three_channels=sum(n == 3 for n in joins), joined_channels=sum(joins), events=dict(events))
            for actor in actors:
                if actor.get('channels',0)<3:
                    readers.append(asyncio.create_task(fallback_poll(session,actor)))
            await asyncio.gather(*(snapshot(session, a) for a in actors))
            note('simultaneous_boot', employees=len(actors), peak_inflight_requests=peak)
            branches = collections.defaultdict(list)
            for a in actors:
                branches[a['branch_id']].append(a)
            drivers = [a for a in actors if a['job'] == 'driver']
            await asyncio.gather(*(rpc(session, a, 'dlv_set_my_driver_duty', {'p_state': 'available'}) for a in drivers))
            work = []
            for bid, members in branches.items():
                ds = [a for a in members if a['job'] == 'driver']
                cc = [a for a in members if a['job'] == 'callcenter']
                kitchens = [a for a in members if a['job'] == 'kitchen']
                supervisors = [a for a in members if a['job'] == 'supervisor']
                for i in range(TARGET_ORDERS // len(branches)):
                    d=ds[i % len(ds)]
                    work.append(dict(driver=d, callcenter=cc[i % len(cc)], kitchen=kitchens[i % len(kitchens)], supervisor=supervisors[i % len(supervisors)], branch=bid))
            async def create(w, i):
                if i in RESUME_BY_INDEX:
                    w['saved']=RESUME_BY_INDEX[i];w['id']=w['saved']['id'];return
                w['id'] = await rpc(session, w['callcenter'], 'dlv_create_order', {'p_order_no': 'QA200-c6d9-'+str(TARGET_USERS)+'-'+str(TARGET_ORDERS)+'-'+str(i), 'p_customer': 'QA synthetic customer', 'p_phone': '', 'p_address': 'QA synthetic address', 'p_notes': 'Disposable load test; no delivery', 'p_branch_id': w['branch'], 'p_callcenter_staff_id': w['callcenter']['staff_id']})
            await asyncio.gather(*(create(w, i) for i, w in enumerate(work)))
            verify(len({w['id'] for w in work}) == TARGET_ORDERS, 'unique_created_orders')
            note('create_orders', orders=len(work))
            await asyncio.gather(*(rpc(session, w['kitchen'], 'dlv_kitchen_forward', {'p_order_id': w['id'], 'p_note': 'QA'}) for w in work if not RESUME_ORDERS or w['saved']['workflow_stage'] in ('new','kitchen_received')))
            await asyncio.gather(*(rpc(session, w['supervisor'], 'dlv_supervisor_receive', {'p_order_id': w['id'], 'p_note': 'QA'}) for w in work if not RESUME_ORDERS or w['saved']['workflow_stage']=='kitchen_ready'))
            await asyncio.gather(*(rpc(session, w['supervisor'], 'dlv_assign_driver', {'p_order_id': w['id'], 'p_driver': w['driver']['user_id'], 'p_note': 'QA'}) for w in work if not RESUME_ORDERS or w['saved']['driver_id'] is None))
            await asyncio.gather(*(rpc(session, w['driver'], 'dlv_set_status', {'p_id': w['id'], 'p_to': 'received'}) for w in work if not RESUME_ORDERS or w['saved']['status']=='new'))
            await asyncio.gather(*(rpc(session, w['driver'], 'dlv_set_status', {'p_id': w['id'], 'p_to': 'out'}) for w in work if not RESUME_ORDERS or w['saved']['status'] in ('new','received')))
            note('workflow_to_out', orders=len(work))
            for wave in range(3):
                async def gps(d):
                    r = await rpc(session, d, 'dlv_update_location_v2', {'p_lat': 30.05 + wave*0.00003, 'p_lng': 31.20 + wave*0.00003, 'p_acc': 8, 'p_recorded_at': datetime.datetime.now(datetime.timezone.utc).isoformat()})
                    verify(r.get('accepted') is True, 'gps_sample_accepted')
                await asyncio.gather(*(gps(d) for d in drivers))
                if wave < 2:
                    await asyncio.sleep(3)
            note('gps', drivers=len(drivers), submitted_samples=len(drivers)*3, simulated=True)
            async def isolate(a):
                other = next(b for b in manifest['branches'] if b['company_id'] != a['company_id'])
                rows = await request(session, a, 'foreign_branch_read', 'GET', '/rest/v1/dlv_orders?select=id&branch_id=eq.'+str(other['branch_id']))
                verify(rows == [], 'foreign_branch_zero_rows')
                if a['job'] in ('manager', 'supervisor'):
                    result = await rpc(session, a, 'dlv_map_locations', {'p_branch': other['branch_id']}, expected=(403,))
                    verify(result.get('code') == '42501', 'foreign_map_denied')
            await asyncio.gather(*(isolate(a) for a in actors))
            note('tenant_isolation', employees_checked=len(actors))
            sent = []
            for bid, members in branches.items():
                managers = [a for a in members if a['job'] == 'manager']
                recipients = [a for a in members if a['job'] != 'manager']
                async def send(m, target):
                    req = str(uuid.uuid4())
                    mid = await rpc(session, m, 'dlv_team_send', {'p_recipient': target['user_id'], 'p_body': 'QA200 synthetic test message; ignore', 'p_request': req})
                    sent.append((m, target, mid))
                await asyncio.gather(*(send(managers[i % len(managers)], a) for i, a in enumerate(recipients)))
            async def receive(m, a, mid):
                inbox = await rpc(session, a, 'dlv_team_inbox')
                verify(any(x['id'] == mid for x in inbox), 'message_in_recipient_inbox')
                await rpc(session, a, 'dlv_team_ack', {'p_id': mid, 'p_read': False})
                await rpc(session, a, 'dlv_team_ack', {'p_id': mid, 'p_read': True})
                wrong = next(x for x in actors if x['branch_id'] != a['branch_id'])
                verify(await rpc(session, wrong, 'dlv_team_ack', {'p_id': mid, 'p_read': True}) is False, 'wrong_recipient_ack_denied')
            await asyncio.gather(*(receive(*row) for row in sent))
            note('private_messages', messages=len(sent), delivered_and_read=len(sent), broadcasts=events['staff_broadcast'])
            await asyncio.gather(*(rpc(session, w['driver'], 'dlv_set_status', {'p_id': w['id'], 'p_to': 'delivered'}) for w in work if not RESUME_ORDERS or w['saved']['status']!='delivered'))
            await asyncio.gather(*(snapshot(session, a) for a in actors))
            day = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=2))).strftime('%Y-%m-%d')
            async def report(a):
                r = await rpc(session, a, 'dlv_daily_branch_report', {'p_branch_id': a['branch_id'], 'p_day': day})
                verify(r['orders']['total'] == (TARGET_ORDERS+BASELINE_ORDERS)//len(branches) and r['orders']['delivered'] == (TARGET_ORDERS+BASELINE_ORDERS)//len(branches), 'daily_report_counts')
            await asyncio.gather(*(report(a) for a in actors if a['job'] == 'manager'))
            note('delivered_and_reports', orders=TARGET_ORDERS, branch_reports=sum(a['job']=='manager' for a in actors))
            verify(events['foreign_branch_leak'] == 0 and events['foreign_driver_leak'] == 0, 'realtime_no_cross_scope_payload')
            evidence['completed'] = True
            evidence['all_clients_realtime'] = all(a.get('channels')==3 for a in actors)
            evidence['test_driver_realtime_cap'] = 200
            evidence['activity_rate_limit_rps'] = 20
            evidence['realtime_data_observed'] = events['postgres_changes']>0 and events['staff_broadcast']>0
        except Exception as e:
            evidence['completed'] = False
            evidence['findings'].append(type(e).__name__+': '+str(e))
            note('stopped_on_error', error=str(e))
        finally:
            await asyncio.sleep(5)
            await asyncio.gather(*(ws.close() for ws in connections), return_exceptions=True)
            for t in readers:
                t.cancel()
            await asyncio.gather(*readers, return_exceptions=True)
            # Sessions are revoked by the exact-tag SQL cleanup after evidence inspection.
    evidence.update(ended_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), peak_inflight_requests=peak, assertions=dict(checks), realtime_events=dict(events))
    evidence['metrics'] = {}
    for label, rows in metrics.items():
        values = sorted(x['ms'] for x in rows)
        evidence['metrics'][label] = {'requests': len(rows), 'http_statuses': dict(collections.Counter(x['status'] for x in rows)), 'p50_ms': round(statistics.median(values), 2), 'p95_ms': values[min(len(values)-1, int(len(values)*.95))], 'max_ms': max(values)}
    save()
    print(json.dumps({'completed': evidence.get('completed'), 'requests': sum(len(v) for v in metrics.values()), 'events': dict(events), 'findings': evidence['findings']}, ensure_ascii=False), flush=True)

if __name__ == '__main__':
    asyncio.run(main())
