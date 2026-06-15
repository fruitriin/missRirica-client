import './style.css'

interface AppVersion {
  id: string;
  name: string;
  version: string;
  description: string;
  url: string;
  port: number;
}

const apps: AppVersion[] = [
  {
    id: 'app-v1',
    name: 'Counter App',
    version: '1.0.0',
    description: 'Simple counter with reset button',
    url: 'http://localhost:5173',
    port: 5173
  },
  {
    id: 'app-v2',
    name: 'Todo App',
    version: '2.0.0',
    description: 'Todo list with add, check, and delete',
    url: 'http://localhost:5174',
    port: 5174
  },
  {
    id: 'app-v3',
    name: 'Weather App',
    version: '3.0.0',
    description: 'Random weather generator for cities',
    url: 'http://localhost:5175',
    port: 5175
  }
];

function renderApps() {
  return apps.map(app => `
    <div class="app-card" style="border: 1px solid #ccc; padding: 15px; margin: 10px 0; border-radius: 8px;">
      <h3>${app.name} (v${app.version})</h3>
      <p>${app.description}</p>
      <p><small>Port: ${app.port}</small></p>
      <button data-app="${app.id}" data-url="${app.url}">Launch App</button>
    </div>
  `).join('');
}

document.querySelector<HTMLDivElement>('#app')!.innerHTML = `
  <div>
    <h1>Version Switcher</h1>
    <p>Select an app version to launch:</p>
    <div id="app-list">
      ${renderApps()}
    </div>
    <div id="iframe-container" style="margin-top: 20px; display: none;">
      <button id="close-iframe">Close App</button>
      <iframe id="app-iframe" style="width: 100%; height: 500px; border: 1px solid #ccc; margin-top: 10px;"></iframe>
    </div>
    <div style="margin-top: 20px; padding: 15px; background: #f0f0f0; border-radius: 8px;">
      <h3>Development Instructions:</h3>
      <p>1. Start each app in a separate terminal:</p>
      <pre style="background: #fff; padding: 10px; border-radius: 4px;">
cd app-v1 && npm run dev -- --port 5173
cd app-v2 && npm run dev -- --port 5174
cd app-v3 && npm run dev -- --port 5175
      </pre>
      <p>2. Then start this version switcher:</p>
      <pre style="background: #fff; padding: 10px; border-radius: 4px;">
cd version-switcher && npm run dev -- --port 5176
      </pre>
    </div>
  </div>
`

const appList = document.querySelector<HTMLDivElement>('#app-list')!;
const iframeContainer = document.querySelector<HTMLDivElement>('#iframe-container')!;
const appIframe = document.querySelector<HTMLIFrameElement>('#app-iframe')!;
const closeBtn = document.querySelector<HTMLButtonElement>('#close-iframe')!;

appList.addEventListener('click', (e) => {
  const target = e.target as HTMLElement;
  if (target.dataset.app && target.dataset.url) {
    appIframe.src = target.dataset.url;
    iframeContainer.style.display = 'block';
  }
});

closeBtn.addEventListener('click', () => {
  appIframe.src = '';
  iframeContainer.style.display = 'none';
});
