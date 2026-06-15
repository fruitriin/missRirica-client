/**
 * Module Federation approach for version switching
 * This demonstrates how to load actual separate applications dynamically
 */

class ModuleFederationAppManager {
    constructor() {
        this.currentApp = null;
        this.currentModule = null;
        this.appContainer = document.getElementById('app-content');
        this.moduleCache = new Map();

        this.initEventListeners();
    }

    initEventListeners() {
        document.querySelectorAll('.app-button').forEach(button => {
            button.addEventListener('click', async (e) => {
                const version = e.target.dataset.version;
                await this.loadRemoteApp(version);

                document.querySelectorAll('.app-button').forEach(btn => btn.classList.remove('active'));
                e.target.classList.add('active');
            });
        });
    }

    async loadRemoteApp(version) {
        console.log(`Loading remote app: ${version}`);

        // Cleanup current app
        if (this.currentModule && this.currentModule.cleanup) {
            this.currentModule.cleanup();
        }

        this.appContainer.innerHTML = '<div class="loading">Loading remote module...</div>';

        try {
            // Simulate loading from different ports/origins
            const moduleUrl = this.getModuleUrl(version);
            const appModule = await this.importRemoteModule(moduleUrl);

            // Initialize the loaded module
            this.currentModule = appModule;
            await appModule.init(this.appContainer);

            this.currentApp = version;

        } catch (error) {
            console.error(`Failed to load remote app ${version}:`, error);
            this.appContainer.innerHTML = `
                <div class="error">
                    <h3>Failed to load remote app ${version}</h3>
                    <p>${error.message}</p>
                    <p><strong>Note:</strong> This is a simulation. In a real implementation,
                    you would have actual remote modules served from different endpoints.</p>
                </div>
            `;
        }
    }

    getModuleUrl(version) {
        // In a real implementation, these would be actual remote URLs
        const moduleUrls = {
            'v1': 'http://localhost:5173/remoteEntry.js',
            'v2': 'http://localhost:5174/remoteEntry.js',
            'v3': 'http://localhost:5175/remoteEntry.js'
        };
        return moduleUrls[version];
    }

    async importRemoteModule(moduleUrl) {
        // Check cache first
        if (this.moduleCache.has(moduleUrl)) {
            return this.moduleCache.get(moduleUrl);
        }

        // Simulate different remote modules
        const version = moduleUrl.includes('5173') ? 'v1' :
                       moduleUrl.includes('5174') ? 'v2' : 'v3';

        // Since we can't actually load from different origins in this demo,
        // we'll simulate the module structure
        const simulatedModule = this.createSimulatedModule(version);

        this.moduleCache.set(moduleUrl, simulatedModule);
        return simulatedModule;
    }

    createSimulatedModule(version) {
        switch (version) {
            case 'v1':
                return {
                    name: 'CounterApp',
                    version: '1.0.0',
                    init: async (container) => {
                        const { createCounterApp } = await import('./modules/counter-module.js');
                        return createCounterApp(container);
                    },
                    cleanup: () => {
                        console.log('Counter app module cleanup');
                    }
                };

            case 'v2':
                return {
                    name: 'TodoApp',
                    version: '2.0.0',
                    init: async (container) => {
                        const { createTodoApp } = await import('./modules/todo-module.js');
                        return createTodoApp(container);
                    },
                    cleanup: () => {
                        console.log('Todo app module cleanup');
                    }
                };

            case 'v3':
                return {
                    name: 'WeatherApp',
                    version: '3.0.0',
                    init: async (container) => {
                        const { createWeatherApp } = await import('./modules/weather-module.js');
                        return createWeatherApp(container);
                    },
                    cleanup: () => {
                        console.log('Weather app module cleanup');
                    }
                };

            default:
                throw new Error(`Unknown version: ${version}`);
        }
    }

    unloadCurrentApp() {
        if (this.currentModule && this.currentModule.cleanup) {
            this.currentModule.cleanup();
        }

        this.appContainer.innerHTML = '<p>Select an app version to load...</p>';
        this.currentApp = null;
        this.currentModule = null;

        document.querySelectorAll('.app-button').forEach(btn => btn.classList.remove('active'));
    }
}

// Add Module Federation toggle
document.addEventListener('DOMContentLoaded', () => {
    let moduleFederationManager = null;
    let originalManager = window.appManager;

    const federationToggle = document.createElement('button');
    federationToggle.textContent = 'Try Module Federation Mode';
    federationToggle.style.cssText = `
        position: fixed;
        top: 60px;
        right: 10px;
        padding: 10px;
        background: #fd7e14;
        color: white;
        border: none;
        border-radius: 5px;
        cursor: pointer;
        z-index: 1000;
        font-size: 12px;
    `;

    let isFederationMode = false;

    federationToggle.addEventListener('click', () => {
        if (!isFederationMode) {
            // Switch to module federation mode
            window.appManager.unloadCurrentApp();
            moduleFederationManager = new ModuleFederationAppManager();
            window.appManager = moduleFederationManager;
            federationToggle.textContent = 'Back to Regular Mode';
            isFederationMode = true;
        } else {
            // Switch back
            window.appManager.unloadCurrentApp();
            window.appManager = originalManager;
            federationToggle.textContent = 'Try Module Federation Mode';
            isFederationMode = false;
        }
    });

    document.body.appendChild(federationToggle);
});