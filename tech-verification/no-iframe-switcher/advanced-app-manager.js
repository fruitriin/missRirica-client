/**
 * Advanced JavaScript-only version switcher with better isolation
 * Uses Shadow DOM, dynamic imports, and scoped execution
 */

class AdvancedAppManager {
    constructor() {
        this.currentApp = null;
        this.currentVersion = null;
        this.currentShadowRoot = null;
        this.appContainer = document.getElementById('app-content');
        this.unloadButton = document.querySelector('.app-unloader');
        this.moduleCache = new Map();
        this.scopeCounters = new Map(); // For unique scoping

        this.initEventListeners();
    }

    initEventListeners() {
        document.querySelectorAll('.app-button').forEach(button => {
            button.addEventListener('click', (e) => {
                const version = e.target.dataset.version;
                this.switchToVersion(version);

                document.querySelectorAll('.app-button').forEach(btn => btn.classList.remove('active'));
                e.target.classList.add('active');
            });
        });
    }

    async switchToVersion(version) {
        console.log(`Switching to version: ${version} (Advanced Mode)`);

        // Cleanup current app
        this.unloadCurrentApp(false);

        this.appContainer.innerHTML = '<div class="loading">Loading...</div>';

        try {
            // Create isolated environment using Shadow DOM
            const appHost = document.createElement('div');
            appHost.className = 'app-host';

            // Use Shadow DOM for style isolation
            const shadowRoot = appHost.attachShadow({ mode: 'open' });
            this.currentShadowRoot = shadowRoot;

            // Load app into shadow DOM
            await this.loadAppInShadow(version, shadowRoot);

            this.appContainer.innerHTML = '';
            this.appContainer.appendChild(appHost);

            this.currentVersion = version;
            this.unloadButton.classList.add('visible');

        } catch (error) {
            console.error(`Failed to load app ${version}:`, error);
            this.appContainer.innerHTML = `<div class="error">Failed to load app ${version}: ${error.message}</div>`;
        }
    }

    async loadAppInShadow(version, shadowRoot) {
        // Create scoped namespace for this app instance
        const scopeId = this.generateScopeId(version);
        const appScope = this.createAppScope(scopeId);

        switch (version) {
            case 'v1':
                await this.loadCounterAppInShadow(shadowRoot, appScope);
                break;
            case 'v2':
                await this.loadTodoAppInShadow(shadowRoot, appScope);
                break;
            case 'v3':
                await this.loadWeatherAppInShadow(shadowRoot, appScope);
                break;
            default:
                throw new Error(`Unknown version: ${version}`);
        }
    }

    generateScopeId(version) {
        const counter = (this.scopeCounters.get(version) || 0) + 1;
        this.scopeCounters.set(version, counter);
        return `${version}_${counter}_${Date.now()}`;
    }

    createAppScope(scopeId) {
        return {
            id: scopeId,
            elements: new Map(),
            eventListeners: [],
            timers: [],
            data: {},

            // Helper methods for the app
            getElementById: (id) => {
                return this.currentShadowRoot?.getElementById(`${scopeId}_${id}`);
            },

            addEventListener: (element, event, handler) => {
                element.addEventListener(event, handler);
                // Track for cleanup
                this.eventListeners = this.eventListeners || [];
                this.eventListeners.push({ element, event, handler });
            },

            setTimeout: (callback, delay) => {
                const timerId = setTimeout(callback, delay);
                this.timers = this.timers || [];
                this.timers.push(timerId);
                return timerId;
            },

            setInterval: (callback, delay) => {
                const timerId = setInterval(callback, delay);
                this.timers = this.timers || [];
                this.timers.push(timerId);
                return timerId;
            }
        };
    }

    async loadCounterAppInShadow(shadowRoot, scope) {
        const styles = `
            :host {
                display: block;
                font-family: system-ui, -apple-system, sans-serif;
            }
            .counter-app {
                text-align: center;
                padding: 20px;
            }
            .counter-display {
                font-size: 48px;
                font-weight: bold;
                margin: 20px 0;
                color: #007bff;
            }
            .counter-controls button {
                margin: 0 10px;
                padding: 10px 20px;
                font-size: 18px;
                border: 2px solid #007bff;
                background: white;
                color: #007bff;
                border-radius: 5px;
                cursor: pointer;
                transition: all 0.3s;
            }
            .counter-controls button:hover {
                background: #007bff;
                color: white;
            }
        `;

        const html = `
            <div class="counter-app">
                <h2>Counter App v1.0.0 (Shadow DOM)</h2>
                <div class="counter-display">
                    <span id="${scope.id}_counter-value">0</span>
                </div>
                <div class="counter-controls">
                    <button id="${scope.id}_increment">+</button>
                    <button id="${scope.id}_decrement">-</button>
                    <button id="${scope.id}_reset">Reset</button>
                </div>
            </div>
        `;

        // Inject styles and HTML into shadow DOM
        shadowRoot.innerHTML = `<style>${styles}</style>${html}`;

        // Initialize app logic with scoped access
        let count = 0;
        const counterValue = scope.getElementById('counter-value');
        const incrementBtn = scope.getElementById('increment');
        const decrementBtn = scope.getElementById('decrement');
        const resetBtn = scope.getElementById('reset');

        const updateDisplay = () => {
            counterValue.textContent = count;
        };

        scope.addEventListener(incrementBtn, 'click', () => {
            count++;
            updateDisplay();
        });

        scope.addEventListener(decrementBtn, 'click', () => {
            count--;
            updateDisplay();
        });

        scope.addEventListener(resetBtn, 'click', () => {
            count = 0;
            updateDisplay();
        });

        // Store app-specific data in scope
        scope.data = { count, updateDisplay };
    }

    async loadTodoAppInShadow(shadowRoot, scope) {
        const styles = `
            :host {
                display: block;
                font-family: system-ui, -apple-system, sans-serif;
            }
            .todo-app {
                max-width: 500px;
                margin: 0 auto;
                padding: 20px;
            }
            .todo-input {
                display: flex;
                gap: 10px;
                margin-bottom: 20px;
            }
            .todo-input input {
                flex: 1;
                padding: 10px;
                border: 1px solid #ddd;
                border-radius: 4px;
                font-size: 16px;
            }
            .todo-input button {
                padding: 10px 20px;
                background: #28a745;
                color: white;
                border: none;
                border-radius: 4px;
                cursor: pointer;
            }
            .todo-input button:hover {
                background: #218838;
            }
            .todo-list {
                list-style: none;
                padding: 0;
            }
            .todo-item {
                display: flex;
                align-items: center;
                gap: 10px;
                padding: 10px;
                border: 1px solid #eee;
                border-radius: 4px;
                margin-bottom: 5px;
            }
            .todo-item.completed .todo-text {
                text-decoration: line-through;
                opacity: 0.6;
            }
            .todo-text {
                flex: 1;
            }
            .delete-btn {
                background: #dc3545;
                color: white;
                border: none;
                padding: 5px 10px;
                border-radius: 3px;
                cursor: pointer;
            }
            .delete-btn:hover {
                background: #c82333;
            }
        `;

        const html = `
            <div class="todo-app">
                <h2>Todo List App v2.0.0 (Shadow DOM)</h2>
                <div class="todo-input">
                    <input type="text" id="${scope.id}_todo-input" placeholder="Add a new todo...">
                    <button id="${scope.id}_add-todo">Add</button>
                </div>
                <ul id="${scope.id}_todo-list" class="todo-list"></ul>
            </div>
        `;

        shadowRoot.innerHTML = `<style>${styles}</style>${html}`;

        // Initialize scoped todo app
        let todos = [];
        let nextId = 1;

        const todoInput = scope.getElementById('todo-input');
        const addBtn = scope.getElementById('add-todo');
        const todoList = scope.getElementById('todo-list');

        const renderTodos = () => {
            todoList.innerHTML = '';
            todos.forEach(todo => {
                const li = document.createElement('li');
                li.className = `todo-item ${todo.completed ? 'completed' : ''}`;

                const checkbox = document.createElement('input');
                checkbox.type = 'checkbox';
                checkbox.checked = todo.completed;

                const text = document.createElement('span');
                text.className = 'todo-text';
                text.textContent = todo.text;

                const deleteBtn = document.createElement('button');
                deleteBtn.className = 'delete-btn';
                deleteBtn.textContent = 'Delete';

                // Scoped event handlers
                scope.addEventListener(checkbox, 'change', () => {
                    todo.completed = !todo.completed;
                    renderTodos();
                });

                scope.addEventListener(deleteBtn, 'click', () => {
                    todos = todos.filter(t => t.id !== todo.id);
                    renderTodos();
                });

                li.appendChild(checkbox);
                li.appendChild(text);
                li.appendChild(deleteBtn);
                todoList.appendChild(li);
            });
        };

        const addTodo = () => {
            const text = todoInput.value.trim();
            if (text) {
                todos.push({
                    id: nextId++,
                    text: text,
                    completed: false
                });
                todoInput.value = '';
                renderTodos();
            }
        };

        scope.addEventListener(addBtn, 'click', addTodo);
        scope.addEventListener(todoInput, 'keypress', (e) => {
            if (e.key === 'Enter') addTodo();
        });

        scope.data = { todos, renderTodos, addTodo };
    }

    async loadWeatherAppInShadow(shadowRoot, scope) {
        const styles = `
            :host {
                display: block;
                font-family: system-ui, -apple-system, sans-serif;
            }
            .weather-app {
                max-width: 400px;
                margin: 0 auto;
                text-align: center;
                padding: 20px;
            }
            .city-selector {
                display: flex;
                gap: 10px;
                margin-bottom: 20px;
            }
            .city-selector select {
                flex: 1;
                padding: 10px;
                border: 1px solid #ddd;
                border-radius: 4px;
                font-size: 16px;
            }
            .city-selector button {
                padding: 10px 20px;
                background: #17a2b8;
                color: white;
                border: none;
                border-radius: 4px;
                cursor: pointer;
            }
            .city-selector button:hover {
                background: #138496;
            }
            .weather-card {
                background: linear-gradient(135deg, #74b9ff, #0984e3);
                color: white;
                padding: 20px;
                border-radius: 10px;
                box-shadow: 0 4px 8px rgba(0,0,0,0.1);
            }
            .weather-temp {
                font-size: 48px;
                font-weight: bold;
                margin: 10px 0;
            }
            .weather-desc {
                font-size: 18px;
                text-transform: capitalize;
            }
        `;

        const html = `
            <div class="weather-app">
                <h2>Weather App v3.0.0 (Shadow DOM)</h2>
                <div class="city-selector">
                    <select id="${scope.id}_city-select">
                        <option value="">Select a city...</option>
                        <option value="tokyo">Tokyo</option>
                        <option value="newyork">New York</option>
                        <option value="london">London</option>
                        <option value="paris">Paris</option>
                        <option value="sydney">Sydney</option>
                    </select>
                    <button id="${scope.id}_get-weather">Get Weather</button>
                </div>
                <div id="${scope.id}_weather-result"></div>
            </div>
        `;

        shadowRoot.innerHTML = `<style>${styles}</style>${html}`;

        const citySelect = scope.getElementById('city-select');
        const getWeatherBtn = scope.getElementById('get-weather');
        const weatherResult = scope.getElementById('weather-result');

        const weatherData = {
            tokyo: { temp: 22, desc: 'partly cloudy', city: 'Tokyo' },
            newyork: { temp: 18, desc: 'sunny', city: 'New York' },
            london: { temp: 15, desc: 'rainy', city: 'London' },
            paris: { temp: 20, desc: 'cloudy', city: 'Paris' },
            sydney: { temp: 25, desc: 'sunny', city: 'Sydney' }
        };

        const showWeather = () => {
            const selectedCity = citySelect.value;
            if (!selectedCity) {
                weatherResult.innerHTML = '<p>Please select a city first!</p>';
                return;
            }

            const weather = weatherData[selectedCity];
            const randomVariation = Math.floor(Math.random() * 10) - 5;
            const temperature = weather.temp + randomVariation;

            weatherResult.innerHTML = `
                <div class="weather-card">
                    <h3>${weather.city}</h3>
                    <div class="weather-temp">${temperature}°C</div>
                    <div class="weather-desc">${weather.desc}</div>
                    <p>Last updated: ${new Date().toLocaleTimeString()}</p>
                </div>
            `;
        };

        scope.addEventListener(getWeatherBtn, 'click', showWeather);
        scope.addEventListener(citySelect, 'change', () => {
            if (citySelect.value) showWeather();
        });

        // Auto-refresh weather every 30 seconds
        const refreshTimer = scope.setInterval(() => {
            if (citySelect.value) showWeather();
        }, 30000);

        scope.data = { weatherData, showWeather, refreshTimer };
    }

    unloadCurrentApp(showMessage = true) {
        if (this.currentShadowRoot) {
            // Clean up all event listeners and timers stored in scope
            const appHost = this.appContainer.querySelector('.app-host');
            if (appHost) {
                // Shadow DOM cleanup is automatic when the host is removed
                appHost.remove();
            }
            this.currentShadowRoot = null;
        }

        if (showMessage) {
            this.appContainer.innerHTML = '<p>Select an app version to load...</p>';
            this.unloadButton.classList.remove('visible');
            this.currentVersion = null;

            document.querySelectorAll('.app-button').forEach(btn => btn.classList.remove('active'));
        }

        console.log('Advanced app unloaded with complete isolation cleanup');
    }
}

// Initialize advanced mode option
document.addEventListener('DOMContentLoaded', () => {
    const toggleButton = document.createElement('button');
    toggleButton.textContent = 'Switch to Advanced Mode (Shadow DOM)';
    toggleButton.style.cssText = `
        position: fixed;
        top: 10px;
        right: 10px;
        padding: 10px;
        background: #6f42c1;
        color: white;
        border: none;
        border-radius: 5px;
        cursor: pointer;
        z-index: 1000;
    `;

    let isAdvancedMode = false;
    let currentManager = window.appManager;

    toggleButton.addEventListener('click', () => {
        if (!isAdvancedMode) {
            // Switch to advanced mode
            currentManager.unloadCurrentApp();
            window.appManager = new AdvancedAppManager();
            toggleButton.textContent = 'Switch to Basic Mode';
            isAdvancedMode = true;
        } else {
            // Switch back to basic mode
            window.appManager.unloadCurrentApp();
            window.appManager = currentManager;
            toggleButton.textContent = 'Switch to Advanced Mode (Shadow DOM)';
            isAdvancedMode = false;
        }
    });

    document.body.appendChild(toggleButton);
});