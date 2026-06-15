/**
 * JavaScript-only version switcher without iframe
 * Uses dynamic imports and DOM manipulation
 */

class AppManager {
    constructor() {
        this.currentApp = null;
        this.currentVersion = null;
        this.currentCleanup = null;
        this.appContainer = document.getElementById('app-content');
        this.unloadButton = document.querySelector('.app-unloader');

        this.initEventListeners();
    }

    initEventListeners() {
        document.querySelectorAll('.app-button').forEach(button => {
            button.addEventListener('click', (e) => {
                const version = e.target.dataset.version;
                this.switchToVersion(version);

                // Update button states
                document.querySelectorAll('.app-button').forEach(btn => btn.classList.remove('active'));
                e.target.classList.add('active');
            });
        });
    }

    async switchToVersion(version) {
        console.log(`Switching to version: ${version}`);

        // Cleanup current app if exists
        if (this.currentCleanup) {
            this.currentCleanup();
            this.currentCleanup = null;
        }

        // Clear container
        this.appContainer.innerHTML = '<div class="loading">Loading...</div>';

        try {
            // Dynamically load and initialize the app
            const cleanup = await this.loadApp(version);
            this.currentVersion = version;
            this.currentCleanup = cleanup;
            this.unloadButton.classList.add('visible');
        } catch (error) {
            console.error(`Failed to load app ${version}:`, error);
            this.appContainer.innerHTML = `<div class="error">Failed to load app ${version}: ${error.message}</div>`;
        }
    }

    async loadApp(version) {
        switch (version) {
            case 'v1':
                return await this.loadCounterApp();
            case 'v2':
                return await this.loadTodoApp();
            case 'v3':
                return await this.loadWeatherApp();
            default:
                throw new Error(`Unknown version: ${version}`);
        }
    }

    // Counter App (v1)
    async loadCounterApp() {
        const appHtml = `
            <div class="counter-app">
                <h2>Counter App v1.0.0</h2>
                <div class="counter-display">
                    <span id="counter-value">0</span>
                </div>
                <div class="counter-controls">
                    <button id="increment">+</button>
                    <button id="decrement">-</button>
                    <button id="reset">Reset</button>
                </div>
            </div>
        `;

        const appStyles = `
            .counter-app {
                text-align: center;
                font-family: Arial, sans-serif;
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

        // Inject HTML and styles
        this.injectStyles('counter-app-styles', appStyles);
        this.appContainer.innerHTML = appHtml;

        // Initialize app logic
        let count = 0;
        const counterValue = document.getElementById('counter-value');
        const incrementBtn = document.getElementById('increment');
        const decrementBtn = document.getElementById('decrement');
        const resetBtn = document.getElementById('reset');

        const updateDisplay = () => {
            counterValue.textContent = count;
        };

        incrementBtn.addEventListener('click', () => {
            count++;
            updateDisplay();
        });

        decrementBtn.addEventListener('click', () => {
            count--;
            updateDisplay();
        });

        resetBtn.addEventListener('click', () => {
            count = 0;
            updateDisplay();
        });

        // Return cleanup function
        return () => {
            this.removeStyles('counter-app-styles');
            console.log('Counter app cleaned up');
        };
    }

    // Todo App (v2)
    async loadTodoApp() {
        const appHtml = `
            <div class="todo-app">
                <h2>Todo List App v2.0.0</h2>
                <div class="todo-input">
                    <input type="text" id="todo-input" placeholder="Add a new todo...">
                    <button id="add-todo">Add</button>
                </div>
                <ul id="todo-list"></ul>
            </div>
        `;

        const appStyles = `
            .todo-app {
                max-width: 500px;
                margin: 0 auto;
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
            #todo-list {
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

        this.injectStyles('todo-app-styles', appStyles);
        this.appContainer.innerHTML = appHtml;

        // Initialize app logic
        let todos = [];
        let nextId = 1;

        const todoInput = document.getElementById('todo-input');
        const addBtn = document.getElementById('add-todo');
        const todoList = document.getElementById('todo-list');

        const renderTodos = () => {
            todoList.innerHTML = '';
            todos.forEach(todo => {
                const li = document.createElement('li');
                li.className = `todo-item ${todo.completed ? 'completed' : ''}`;
                li.innerHTML = `
                    <input type="checkbox" ${todo.completed ? 'checked' : ''}
                           onchange="appManager.toggleTodo(${todo.id})">
                    <span class="todo-text">${todo.text}</span>
                    <button class="delete-btn" onclick="appManager.deleteTodo(${todo.id})">Delete</button>
                `;
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

        // Expose functions globally for onclick handlers
        window.appManager = window.appManager || {};
        window.appManager.toggleTodo = (id) => {
            const todo = todos.find(t => t.id === id);
            if (todo) {
                todo.completed = !todo.completed;
                renderTodos();
            }
        };

        window.appManager.deleteTodo = (id) => {
            todos = todos.filter(t => t.id !== id);
            renderTodos();
        };

        addBtn.addEventListener('click', addTodo);
        todoInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') addTodo();
        });

        return () => {
            this.removeStyles('todo-app-styles');
            // Clean up global functions
            if (window.appManager) {
                delete window.appManager.toggleTodo;
                delete window.appManager.deleteTodo;
            }
            console.log('Todo app cleaned up');
        };
    }

    // Weather App (v3)
    async loadWeatherApp() {
        const appHtml = `
            <div class="weather-app">
                <h2>Weather App v3.0.0</h2>
                <div class="city-selector">
                    <select id="city-select">
                        <option value="">Select a city...</option>
                        <option value="tokyo">Tokyo</option>
                        <option value="newyork">New York</option>
                        <option value="london">London</option>
                        <option value="paris">Paris</option>
                        <option value="sydney">Sydney</option>
                    </select>
                    <button id="get-weather">Get Weather</button>
                </div>
                <div id="weather-result"></div>
            </div>
        `;

        const appStyles = `
            .weather-app {
                max-width: 400px;
                margin: 0 auto;
                text-align: center;
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

        this.injectStyles('weather-app-styles', appStyles);
        this.appContainer.innerHTML = appHtml;

        // Initialize app logic
        const citySelect = document.getElementById('city-select');
        const getWeatherBtn = document.getElementById('get-weather');
        const weatherResult = document.getElementById('weather-result');

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
            const randomVariation = Math.floor(Math.random() * 10) - 5; // ±5 degrees
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

        getWeatherBtn.addEventListener('click', showWeather);
        citySelect.addEventListener('change', () => {
            if (citySelect.value) showWeather();
        });

        return () => {
            this.removeStyles('weather-app-styles');
            console.log('Weather app cleaned up');
        };
    }

    // Utility methods
    injectStyles(id, css) {
        // Remove existing styles with same id
        this.removeStyles(id);

        const style = document.createElement('style');
        style.id = id;
        style.textContent = css;
        document.head.appendChild(style);
    }

    removeStyles(id) {
        const existingStyle = document.getElementById(id);
        if (existingStyle) {
            existingStyle.remove();
        }
    }

    unloadCurrentApp() {
        if (this.currentCleanup) {
            this.currentCleanup();
            this.currentCleanup = null;
        }

        this.appContainer.innerHTML = '<p>Select an app version to load...</p>';
        this.unloadButton.classList.remove('visible');
        this.currentVersion = null;

        // Remove active state from buttons
        document.querySelectorAll('.app-button').forEach(btn => btn.classList.remove('active'));

        console.log('Current app unloaded');
    }
}

// Initialize the app manager
const appManager = new AppManager();

// Make it globally accessible for onclick handlers
window.appManager = appManager;