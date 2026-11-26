'use strict';
let token=location.hash.slice(1)||sessionStorage.getItem('amid-panel-token')||'';if(token)sessionStorage.setItem('amid-panel-token',token);history.replaceState(null,'','/');
const $=id=>document.getElementById(id);
const states=['Вимкнений','Пошук нуля','Відступ','Готовий','Рух','Заспокоєння','Вимірювання','Утримування','Немає сигналу','Помилка','Малий рух'];
let busy=false,connected=false;
async function api(path,body){const r=await fetch('/api/'+path,{method:body?'POST':'GET',headers:{'Authorization':'Bearer '+token,...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{})});const d=await r.json();if(!r.ok)throw Error(d.error||'Помилка запиту');return d;}
function buttons(enabled){document.querySelectorAll('[data-command]').forEach(b=>b.disabled=!enabled);}
buttons(false);
async function refresh(){if(busy||!token)return;busy=true;try{
 await api('heartbeat',{});const s=await api('state');connected=s.alive&&s.ready;
 $('connection').textContent=connected?'● Міст працює':s.alive?'Підключення до Mega…':'Міст завершив роботу';
 $('mode').textContent=s.mode==='radio'?'РАДІО + ПРИВІД':'ПРИВІД';
 $('state').textContent=states[s.state]||'Невідомий';$('steps').textContent=s.position??'—';$('homed').textContent=s.homed===null?'—':s.homed?'Виконано':'Потрібен ARM';
 $('age').textContent=s.state_age_s===null?'Статус ще не отримано':`Статус: ${s.state_age_s} с тому`;
 const fresh=s.state_age_s!==null&&s.state_age_s<3;buttons(connected&&fresh);
 document.querySelectorAll('.radio').forEach(b=>b.disabled=!connected||!fresh||s.mode!=='radio');$('stop').disabled=!s.alive;
 $('angle').textContent=s.nominal_angle===null?'—':s.nominal_angle+'°';$('needle').style.opacity=s.nominal_angle===null?0:1;$('needle').style.transform=`rotate(${s.nominal_angle??0}deg)`;
 for(const [i,id] of ['left','right','estop'].entries())$(id).textContent=s.inputs?s.inputs[i]===0?'0 · замкнено':'1 · відкрито':'—';
 if(s.last_result){const a=s.last_result.split(' ');$('measurement').textContent=a[5]==='1'?`RSSI ${Number(a[6])/10} dBm · SNR ${Number(a[7])/10} dB · ACK ${a[4]}`:`Недостатньо відповідей · ACK ${a[4]}`;}
 $('events').textContent=s.logs.join('\n');
 $('notice').textContent=!fresh?'Очікування свіжого статусу. Рухові команди недоступні.':s.lease_expired?'З’єднання сторінки втрачалося: STOP запитано. Для руху повтори ARM.':'Команди виконує фізична Mega. ARM, SCAN та JOG запускають рух. Підключення саме по собі руху не запускає.';
}catch(e){connected=false;buttons(false);$('connection').textContent='З’єднання втрачено';$('notice').textContent=e.message;}finally{busy=false;}}
document.querySelectorAll('[data-command]').forEach(b=>b.addEventListener('click',async()=>{try{await api('command',{command:b.dataset.command});$('notice').textContent='Команду передано: '+b.dataset.command+'. Виконання підтверджується подіями Mega.';}catch(e){$('notice').textContent=e.message;}}));
refresh();setInterval(refresh,1000);
