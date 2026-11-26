"""Local records of real received firmware events. Empty sessions contain no invented measurements."""
import csv,json,html,time,os
from pathlib import Path
from datetime import datetime,timezone

COLUMNS=['utc','elapsed_s','window','position_steps','nominal_azimuth_deg','phase','samples','sufficient','rssi_dbm','snr_db','finish_reason','verification']
PHASES={0:'COARSE',1:'FINE',2:'TRACK'}
REASONS={'HOST_TIMEOUT':'Втрачено heartbeat ноутбука: мотор вимкнений, потрібен ARM.',
 'ESTOP_OR_BROKEN_WIRE':'Стоп-кнопка або обрив NC-ланцюга.',
 'TRAVEL_LIMIT':'Спрацював кінцевик під час робочого руху.',
 'CHECK_NC_SWITCHES':'Перевір стоп і правий NC-кінцевик перед ARM.',
 'BOTH_LIMITS':'Обидва кінцевики відкриті: перевір проводку.',
 'HOME_TIMEOUT':'Вичерпано час пошуку нуля.',
 'HOME_TRAVEL':'Лівий кінцевик не знайдено в дозволеному ході.',
 'LEFT_NOT_RELEASED':'Лівий кінцевик не закрився після обмеженого відходу.',
 'RIGHT_LIMIT_DURING_HOME':'Правий кінцевик спрацював під час пошуку нуля.',
 'SOFT_LIMIT':'Запитаний рух виходить за програмний сектор.',
 'IDLE_TIMEOUT':'П’ять хвилин очікування: котушки вимкнено. Перед рухом повтори ARM.'}
def explain(line):return REASONS.get(line.split()[-1],'') if line else ''
def parse_info(line):
    a=line.split()
    if len(a)!=4 or a[:2]!=['INFO','2']:raise ValueError('Firmware v0.2 INFO required')
    rev,maximum=int(a[2]),int(a[3])
    if not 1024<=rev<=65536 or maximum!=rev*3//4:raise ValueError('Invalid calibration declaration')
    return rev,maximum

def parse_result(line,max_pos):
    a=line.split()
    if len(a)!=9 or a[0]!='RESULT':raise ValueError('Malformed RESULT')
    token,pos,phase,count,valid=map(int,a[1:6]);why=a[8]
    if not 0<token<=0xffffffff or not 0<=pos<=max_pos or phase not in PHASES or not 0<=count<=5 or valid not in (0,1):raise ValueError('RESULT out of range')
    if bool(valid)!=(count>=2) or why not in ('ENOUGH','TIMEOUT'):raise ValueError('Contradictory RESULT')
    if valid:
        r,s=int(a[6]),int(a[7])
        if not -1500<=r<0 or not -300<=s<=300:raise ValueError('Invalid RF metrics')
        r,s=r/10,s/10
    else:
        if a[6:8]!=['NA','NA']:raise ValueError('Insufficient samples must have NA metrics')
        r=s=None
    return {'window':token,'position_steps':pos,'phase':PHASES[phase],'samples':count,'sufficient':bool(valid),'rssi_dbm':r,'snr_db':s,'finish_reason':why}

class Journal:
    def __init__(self,path,metadata,max_pos):
        self.path=Path(path);self.path.mkdir(parents=True,exist_ok=False);self.max_pos=max_pos;self.started=time.monotonic();self.rows=[];self.seen=set()
        self.csv_file=(self.path/'measurements.csv').open('w',encoding='utf-8-sig',newline='');self.writer=csv.DictWriter(self.csv_file,fieldnames=COLUMNS);self.writer.writeheader();self.csv_file.flush()
        self.event_file=(self.path/'events.jsonl').open('w',encoding='utf-8')
        (self.path/'session.json').write_text(json.dumps({**metadata,'verification':'unverified','angles':'nominal commanded steps; no encoder','max_position_steps':max_pos},ensure_ascii=False,indent=2),encoding='utf-8')
        self.render()
    def event(self,kind,**values):
        self.event_file.write(json.dumps({'elapsed_s':round(time.monotonic()-self.started,3),'kind':kind,**values},ensure_ascii=False)+'\n');self.event_file.flush()
    def record(self,result,epoch):
        key=(epoch,result['window'])
        if key in self.seen:return False
        row={**result,'utc':datetime.now(timezone.utc).isoformat(timespec='milliseconds'),'elapsed_s':round(time.monotonic()-self.started,3),'nominal_azimuth_deg':round(result['position_steps']/self.max_pos*270-135,2),'verification':'unverified'}
        self.writer.writerow(row);self.csv_file.flush();os.fsync(self.csv_file.fileno());self.rows.append(row);self.seen.add(key);self.render();return True
    def render(self):
        valid=[r for r in self.rows if r['sufficient']]
        e=lambda x:html.escape(str(x))
        summary='Завершених вікон вимірювання ще немає.'
        if self.rows:summary=f'Завершено вікон: {len(self.rows)}. Достатньо відповідей: {len(valid)}.'
        if valid:
            best=max(valid,key=lambda r:(r['rssi_dbm'],r['snr_db']));summary+=f" Найсильніше записане спостереження: {best['nominal_azimuth_deg']}°, RSSI {best['rssi_dbm']} dBm."
        body=''
        for r in self.rows:
            cells=[r['elapsed_s'],r['nominal_azimuth_deg'],r['phase'],r['samples'],'так' if r['sufficient'] else 'недостатньо',r['rssi_dbm'] if r['sufficient'] else '—',r['snr_db'] if r['sufficient'] else '—',r['finish_reason']]
            body+='<tr>'+''.join('<td>'+e(x)+'</td>' for x in cells)+'</tr>'
        text='''<!doctype html><html lang="uk"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AMID Azimuth — журнал</title><style>body{background:#101b26;color:#dfebf1;font:16px system-ui;margin:32px auto;max-width:1100px;padding:0 18px}h1{color:#70e6c3}p{line-height:1.6}.wrap{overflow:auto}table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #355065;padding:12px;text-align:left;white-space:nowrap}th{color:#8de2d1}.tag{color:#e7bd79}small{color:#9db5c5}</style><h1>AMID / Azimuth 0.5</h1><p class="tag">Спостереження стенда · незалежно не перевірені</p>'''
        text+='<p>'+e(summary)+'</p><p>Кут обчислено з командних кроків. Енкодера немає; фактичне положення треба калібрувати. «Достатньо» означає щонайменше два різні прийняті ACK, а не сертифіковану якість зв’язку.</p><div class="wrap"><table><thead><tr>'+''.join('<th>'+x+'</th>' for x in ['Час сеансу, с','Номінальний кут, °','Етап','ACK','Достатньо','RSSI, dBm','SNR, dB','Завершення'])+'</tr></thead><tbody>'+body+'</tbody></table></div><p><small>CSV містить усі завершені вікна. Події та переривання — у events.jsonl. Відсутні метрики не підміняються нулями. Звіт не визначає дальність, зиск антени або гарантовану доставку рятувальникам. Онови сторінку, щоб побачити нові записи.</small></p></html>'
        temp=self.path/'report.tmp';temp.write_text(text,encoding='utf-8');temp.replace(self.path/'report.html')
    def close(self):self.csv_file.close();self.event_file.close()
