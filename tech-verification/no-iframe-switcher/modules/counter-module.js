/**
 * Counter App Module - Exported as a reusable module
 */

export function createCounterApp(container) {
    console.log('Initializing Counter App Module');

    // Create isolated scope
    const appScope = {
        count: 0,
        elements: {},
        cleanup: []
    };

    // Styles for this module
    const styles = `
        .counter-module {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            text-align: center;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 10px;
            box-shadow: 0 8px 16px rgba(0,0,0,0.1);
        }
        .counter-module h2 {
            margin-top: 0;
            color: #fff;
        }
        .counter-display {
            font-size: 64px;
            font-weight: bold;
            margin: 30px 0;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .counter-controls {
            display: flex;
            justify-content: center;
            gap: 15px;
        }
        .counter-controls button {
            padding: 12px 24px;
            font-size: 18px;
            font-weight: bold;
            border: 2px solid rgba(255,255,255,0.3);
            background: rgba(255,255,255,0.1);
            color: white;
            border-radius: 8px;
            cursor: pointer;
            transition: all 0.3s ease;
            backdrop-filter: blur(10px);
        }
        .counter-controls button:hover {
            background: rgba(255,255,255,0.2);
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.2);
        }
        .counter-controls button:active {
            transform: translateY(0);
        }
        .counter-stats {
            margin-top: 20px;
            font-size: 14px;
            opacity: 0.8;
        }
    `;

    // Create HTML structure
    const html = `
        <div class="counter-module">
            <h2>🔢 Counter App Module v1.0.0</h2>
            <div class="counter-display" id="counter-display">0</div>
            <div class="counter-controls">
                <button id="decrement-btn">➖ Decrement</button>
                <button id="reset-btn">🔄 Reset</button>
                <button id="increment-btn">➕ Increment</button>
            </div>
            <div class="counter-stats" id="counter-stats">
                Total clicks: 0
            </div>
        </div>
    `;

    // Inject styles
    const styleElement = document.createElement('style');
    styleElement.textContent = styles;
    document.head.appendChild(styleElement);
    appScope.cleanup.push(() => styleElement.remove());

    // Set HTML
    container.innerHTML = html;

    // Get elements
    appScope.elements = {
        display: container.querySelector('#counter-display'),
        incrementBtn: container.querySelector('#increment-btn'),
        decrementBtn: container.querySelector('#decrement-btn'),
        resetBtn: container.querySelector('#reset-btn'),
        stats: container.querySelector('#counter-stats')
    };

    // App state
    let totalClicks = 0;

    // Update display function
    const updateDisplay = () => {
        appScope.elements.display.textContent = appScope.count;
        appScope.elements.stats.textContent = `Total clicks: ${totalClicks}`;
    };

    // Event handlers
    const increment = () => {
        appScope.count++;
        totalClicks++;
        updateDisplay();
    };

    const decrement = () => {
        appScope.count--;
        totalClicks++;
        updateDisplay();
    };

    const reset = () => {
        appScope.count = 0;
        totalClicks++;
        updateDisplay();
    };

    // Bind events
    appScope.elements.incrementBtn.addEventListener('click', increment);
    appScope.elements.decrementBtn.addEventListener('click', decrement);
    appScope.elements.resetBtn.addEventListener('click', reset);

    // Store cleanup functions
    appScope.cleanup.push(() => {
        appScope.elements.incrementBtn.removeEventListener('click', increment);
        appScope.elements.decrementBtn.removeEventListener('click', decrement);
        appScope.elements.resetBtn.removeEventListener('click', reset);
    });

    // Keyboard shortcuts
    const handleKeyPress = (event) => {
        switch(event.key) {
            case '+':
            case '=':
                increment();
                break;
            case '-':
                decrement();
                break;
            case 'r':
            case 'R':
                reset();
                break;
        }
    };

    document.addEventListener('keydown', handleKeyPress);
    appScope.cleanup.push(() => {
        document.removeEventListener('keydown', handleKeyPress);
    });

    // Return module interface
    return {
        // Public API
        getCount: () => appScope.count,
        setCount: (value) => {
            appScope.count = value;
            updateDisplay();
        },
        increment,
        decrement,
        reset,

        // Cleanup function
        cleanup: () => {
            console.log('Cleaning up Counter App Module');
            appScope.cleanup.forEach(fn => fn());
            container.innerHTML = '';
        }
    };
}