/* Browser-only controls. No personal data leaves this page. */
(() => {
  'use strict';
  const el = id => document.getElementById(id);
  const say = text => { el('action-detail').textContent = text; };
  const help = () => el('offline-help').showModal();
  let registration, deferredInstall, reloadRequested = false, preparing = false;
  let statusRequest = 0;
  const watched = new WeakSet();
  const registrations = new WeakSet();
  const startupTimer = setTimeout(() => {
    el('startup-message').textContent = 'Завантаження триває довше. Перевір мережу й спробуй ще, якщо екран не відкриється.';
    el('restart-app').hidden = false;
  }, 30000);
  window.amidPwa = {
    startupReady() { clearTimeout(startupTimer); el('startup').hidden = true; },
    startupError() {
      clearTimeout(startupTimer);
      el('startup-message').textContent = 'Не вдалося відкрити програму. Перевір мережу або повтори запуск. Дані не очищуються.';
      el('restart-app').hidden = false;
    }
  };
  el('restart-app').onclick = () => location.reload();
  el('offline-status').onclick = help;
  function network() {
    el('network-detail').textContent = navigator.onLine
      ? 'Браузер бачить мережеве підключення. Це не гарантує доступу до інтернету.'
      : 'Браузер повідомляє, що мережа недоступна.';
  }
  function showState(title, detail) {
    el('offline-status').textContent = title;
    el('offline-detail').textContent = detail;
  }
  function request(worker, type) {
    return new Promise((resolve, reject) => {
      if (!worker) { reject(new Error('worker unavailable')); return; }
      const channel = new MessageChannel();
      const timer = setTimeout(() => { channel.port1.close(); reject(new Error('timeout')); }, 5000);
      channel.port1.onmessage = event => { clearTimeout(timer); channel.port1.close(); resolve(event.data); };
      worker.postMessage({type}, [channel.port2]);
    });
  }
  async function refresh() {
    const ticket = ++statusRequest;
    el('update-app').hidden = !registration?.waiting;
    if (registration?.installing) {
      showState('Офлайн: готую…', 'Зберігаю файли програми. Перше завантаження потребує мережі й вільного місця.');
      return;
    }
    try {
      const state = await request(registration?.active, 'STATUS');
      if (ticket !== statusRequest) return;
      showState(state.ready ? 'Офлайн: файли збережені' : 'Офлайн: потрібна підготовка',
        state.ready
          ? `Збережено ${state.files} файлів програми. Закрий і знову відкрий її та перевір без мережі. Нотатки зберігаються окремо.`
          : 'Частина файлів відсутня. Натисни «Повторити підготовку» з доступною мережею.');
    } catch (_) {
      if (ticket !== statusRequest) return;
      showState('Офлайн: ще не підтверджено', registration?.waiting
        ? 'Є нова версія з перевіркою офлайн-файлів. Збережи відкриту нотатку перед оновленням.'
        : 'Не вдалося підтвердити збереження файлів. Спробуй підготовку з мережею. Програма залишається доступною, якщо браузер може її відкрити.');
    }
  }
  function watch(worker) {
    if (!worker || watched.has(worker)) return;
    watched.add(worker);
    worker.addEventListener('statechange', () => {
      if (worker.state === 'redundant') {
        ++statusRequest;
        showState('Офлайн: підготовка не вдалася', 'Файли не вдалося зберегти. Перевір мережу та вільне місце, потім повтори. Попередня версія й нотатки не очищуються.');
      } else { refresh(); }
    });
  }
  async function prepare() {
    if (preparing) return;
    preparing = true; el('prepare-offline').disabled = true;
    try {
      registration = await navigator.serviceWorker.register('amid-sw.js', {updateViaCache: 'none'});
      if (!registrations.has(registration)) {
        registrations.add(registration);
        registration.addEventListener('updatefound', () => { watch(registration.installing); refresh(); });
      }
      watch(registration.installing);
      if (registration.active && !registration.installing && !registration.waiting) {
        // Repair only missing files. Failure leaves every existing file intact.
        const current = await request(registration.active, 'STATUS').catch(() => null);
        if (current && !current.ready) {
          registration.active.postMessage({type: 'REPAIR'});
          showState('Офлайн: готую…', 'Відновлюю відсутні файли програми…');
        } else { await registration.update(); await refresh(); }
      } else { await refresh(); }
    } catch (_) {
      showState('Офлайн: підготовка не вдалася', 'Браузер не зміг підготувати файли. Перевір підключення, вільне місце та дозволи сховища. Нотатки не очищуються.');
    } finally { preparing = false; el('prepare-offline').disabled = false; }
  }
  el('prepare-offline').onclick = prepare;
  el('check-update').onclick = async () => {
    try {
      if (!registration) { await prepare(); return; }
      await registration.update(); watch(registration.installing); await refresh();
      say(registration.waiting ? 'Оновлення готове. Збережи нотатку перед застосуванням.' : 'Перевірку запущено. Якщо є нова версія, вона з’явиться після підготовки файлів.');
    } catch (_) { say('Не вдалося перевірити оновлення. Спробуй із мережею.'); }
  };
  el('update-app').onclick = async () => {
    if (!registration?.waiting) return;
    help();
    say('Збережи нотатку й закрий інші вкладки AMID. Оновлення перезавантажить це вікно.');
    // Confirmation is an ordinary visible page control, not a silent reload.
    let confirm = el('confirm-update');
    if (!confirm) {
      confirm = document.createElement('button'); confirm.id = 'confirm-update';
      confirm.textContent = 'Збережено — оновити це вікно';
      el('action-detail').after(confirm);
    }
    confirm.onclick = async () => {
      reloadRequested = true;
      try {
        const result = await request(registration.waiting, 'ACTIVATE');
        if (!result.accepted) {
          reloadRequested = false;
          say('Спочатку закрий інші вкладки або вікна AMID, щоб не втратити їхні незбережені зміни. Потім повтори.');
        }
      } catch (_) { reloadRequested = false; say('Оновлення ще не готове. Закрий і знову відкрий усі вікна AMID після збереження нотаток.'); }
    };
  };
  window.addEventListener('beforeinstallprompt', event => {
    event.preventDefault(); deferredInstall = event;
  });
  const installed = () => {
    deferredInstall = null; el('install-app').textContent = 'Як відкрити';
  };
  window.addEventListener('appinstalled', installed);
  if (window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true) installed();
  el('install-app').onclick = async () => {
    if (!deferredInstall) { help(); return; }
    const prompt = deferredInstall; deferredInstall = null;
    try { await prompt.prompt(); await prompt.userChoice; }
    catch (_) { help(); say('Скористайся меню браузера для встановлення.'); }
  };
  window.addEventListener('online', network); window.addEventListener('offline', network); network();
  if (!('serviceWorker' in navigator) || !window.isSecureContext) {
    el('prepare-offline').disabled = true; el('check-update').disabled = true;
    showState('Офлайн: недоступно', 'Цей браузер або режим сторінки не підтримує офлайн-файли. Використовуй HTTPS та підтримуваний браузер. Нотатки експортуй окремо.');
    return;
  }
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (reloadRequested) { reloadRequested = false; location.reload(); } else { refresh(); }
  });
  navigator.serviceWorker.addEventListener('message', event => {
    // A failed installing worker can become redundant before its message arrives.
    // Accept only workers observed from this registration, including that final failure.
    if (!watched.has(event.source) && event.source !== registration?.active && event.source !== registration?.waiting) return;
    if (event.data?.type === 'PROGRESS') {
      ++statusRequest;
      showState('Офлайн: готую…', `Збережено ${event.data.done} із ${event.data.total} файлів програми.`);
    } else if (event.data?.type === 'READY') { refresh(); }
    else if (event.data?.type === 'FAILED') {
      ++statusRequest;
      el('offline-detail').setAttribute('data-failure-reason', event.data.reason || 'unknown');
      el('offline-detail').setAttribute('data-failure-file', event.data.file || 'unknown');
      showState('Офлайн: підготовка не вдалася', 'Не всі файли збережені. Перевір мережу та вільне місце, потім повтори. Нотатки не очищуються.');
    }
  });
  prepare();
})();
