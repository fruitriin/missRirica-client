/**
 * Weather App Module - Exported as a reusable module
 */

export function createWeatherApp(container) {
    console.log('Initializing Weather App Module');

    // Create isolated scope
    const appScope = {
        currentCity: null,
        weatherData: {},
        elements: {},
        cleanup: [],
        refreshInterval: null
    };

    const styles = `
        .weather-module {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            max-width: 500px;
            margin: 0 auto;
            padding: 20px;
            background: linear-gradient(135deg, #ff9a9e 0%, #fecfef 50%, #fecfef 100%);
            border-radius: 10px;
            box-shadow: 0 8px 16px rgba(0,0,0,0.1);
            text-align: center;
        }
        .weather-module h2 {
            color: #fff;
            margin-top: 0;
            text-shadow: 1px 1px 2px rgba(0,0,0,0.2);
        }
        .city-selector {
            display: flex;
            gap: 10px;
            margin-bottom: 25px;
            background: rgba(255,255,255,0.1);
            padding: 15px;
            border-radius: 8px;
            backdrop-filter: blur(10px);
        }
        .city-selector select {
            flex: 1;
            padding: 12px;
            border: 2px solid rgba(255,255,255,0.3);
            border-radius: 6px;
            font-size: 16px;
            background: rgba(255,255,255,0.9);
            cursor: pointer;
        }
        .city-selector button {
            padding: 12px 20px;
            background: rgba(255,255,255,0.2);
            color: white;
            border: 2px solid rgba(255,255,255,0.3);
            border-radius: 6px;
            cursor: pointer;
            font-weight: bold;
            transition: all 0.3s ease;
        }
        .city-selector button:hover {
            background: rgba(255,255,255,0.3);
            transform: translateY(-1px);
        }
        .weather-display {
            min-height: 200px;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .weather-card {
            background: rgba(255,255,255,0.9);
            padding: 25px;
            border-radius: 15px;
            box-shadow: 0 8px 16px rgba(0,0,0,0.1);
            color: #333;
            width: 100%;
            max-width: 300px;
            backdrop-filter: blur(10px);
        }
        .weather-city {
            font-size: 24px;
            font-weight: bold;
            margin-bottom: 10px;
            color: #2c3e50;
        }
        .weather-temp {
            font-size: 48px;
            font-weight: bold;
            margin: 15px 0;
            color: #e74c3c;
            text-shadow: 1px 1px 2px rgba(0,0,0,0.1);
        }
        .weather-desc {
            font-size: 18px;
            text-transform: capitalize;
            margin-bottom: 15px;
            color: #34495e;
        }
        .weather-details {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px;
            margin-top: 15px;
            font-size: 14px;
        }
        .weather-detail {
            background: rgba(52, 73, 94, 0.1);
            padding: 8px;
            border-radius: 6px;
        }
        .weather-detail strong {
            display: block;
            color: #2c3e50;
        }
        .weather-icon {
            font-size: 48px;
            margin: 10px 0;
        }
        .last-updated {
            font-size: 12px;
            color: #7f8c8d;
            margin-top: 10px;
            font-style: italic;
        }
        .loading {
            color: white;
            font-size: 18px;
            padding: 40px;
        }
        .error {
            color: #e74c3c;
            font-size: 16px;
            padding: 20px;
            background: rgba(255,255,255,0.9);
            border-radius: 8px;
        }
        .weather-actions {
            margin-top: 20px;
            display: flex;
            gap: 10px;
            justify-content: center;
        }
        .action-btn {
            padding: 8px 16px;
            border: 2px solid rgba(255,255,255,0.3);
            background: rgba(255,255,255,0.1);
            color: white;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            transition: all 0.3s ease;
        }
        .action-btn:hover {
            background: rgba(255,255,255,0.2);
        }
        .auto-refresh {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            margin-top: 15px;
            color: white;
            font-size: 14px;
        }
        .auto-refresh input[type="checkbox"] {
            transform: scale(1.2);
        }
    `;

    const html = `
        <div class="weather-module">
            <h2>🌤️ Weather App Module v3.0.0</h2>
            <div class="city-selector">
                <select id="city-select">
                    <option value="">Select a city...</option>
                    <option value="tokyo">🗼 Tokyo, Japan</option>
                    <option value="newyork">🗽 New York, USA</option>
                    <option value="london">🌉 London, UK</option>
                    <option value="paris">🗼 Paris, France</option>
                    <option value="sydney">🏗️ Sydney, Australia</option>
                    <option value="moscow">🏛️ Moscow, Russia</option>
                    <option value="dubai">🏙️ Dubai, UAE</option>
                    <option value="singapore">🏙️ Singapore</option>
                </select>
                <button id="get-weather-btn">Get Weather</button>
            </div>
            <div class="weather-display" id="weather-display">
                <div class="loading">☁️ Select a city to see the weather</div>
            </div>
            <div class="weather-actions">
                <button class="action-btn" id="refresh-btn">🔄 Refresh</button>
                <button class="action-btn" id="share-btn">📤 Share</button>
            </div>
            <div class="auto-refresh">
                <input type="checkbox" id="auto-refresh-checkbox">
                <label for="auto-refresh-checkbox">Auto-refresh every 30 seconds</label>
            </div>
        </div>
    `;

    // Weather data with more details
    appScope.weatherData = {
        tokyo: {
            city: 'Tokyo',
            country: 'Japan',
            baseTemp: 22,
            conditions: ['sunny', 'partly cloudy', 'cloudy', 'light rain'],
            humidity: [60, 80],
            windSpeed: [5, 15],
            pressure: [1010, 1020],
            icon: '🌤️'
        },
        newyork: {
            city: 'New York',
            country: 'USA',
            baseTemp: 18,
            conditions: ['sunny', 'partly cloudy', 'overcast'],
            humidity: [45, 70],
            windSpeed: [8, 20],
            pressure: [1005, 1015],
            icon: '🏙️'
        },
        london: {
            city: 'London',
            country: 'UK',
            baseTemp: 15,
            conditions: ['rainy', 'overcast', 'drizzle', 'foggy'],
            humidity: [75, 90],
            windSpeed: [10, 25],
            pressure: [1000, 1010],
            icon: '🌧️'
        },
        paris: {
            city: 'Paris',
            country: 'France',
            baseTemp: 20,
            conditions: ['sunny', 'partly cloudy', 'cloudy'],
            humidity: [55, 75],
            windSpeed: [6, 18],
            pressure: [1008, 1018],
            icon: '🌤️'
        },
        sydney: {
            city: 'Sydney',
            country: 'Australia',
            baseTemp: 25,
            conditions: ['sunny', 'clear', 'partly cloudy'],
            humidity: [50, 70],
            windSpeed: [12, 22],
            pressure: [1012, 1022],
            icon: '☀️'
        },
        moscow: {
            city: 'Moscow',
            country: 'Russia',
            baseTemp: 8,
            conditions: ['snowy', 'overcast', 'cold', 'freezing'],
            humidity: [70, 85],
            windSpeed: [15, 30],
            pressure: [995, 1005],
            icon: '❄️'
        },
        dubai: {
            city: 'Dubai',
            country: 'UAE',
            baseTemp: 35,
            conditions: ['sunny', 'hot', 'clear', 'dusty'],
            humidity: [30, 50],
            windSpeed: [5, 15],
            pressure: [1015, 1025],
            icon: '🌞'
        },
        singapore: {
            city: 'Singapore',
            country: 'Singapore',
            baseTemp: 30,
            conditions: ['humid', 'partly cloudy', 'thunderstorms', 'tropical'],
            humidity: [80, 95],
            windSpeed: [3, 12],
            pressure: [1008, 1015],
            icon: '🌴'
        }
    };

    // Inject styles
    const styleElement = document.createElement('style');
    styleElement.textContent = styles;
    document.head.appendChild(styleElement);
    appScope.cleanup.push(() => styleElement.remove());

    // Set HTML
    container.innerHTML = html;

    // Get elements
    appScope.elements = {
        citySelect: container.querySelector('#city-select'),
        getWeatherBtn: container.querySelector('#get-weather-btn'),
        weatherDisplay: container.querySelector('#weather-display'),
        refreshBtn: container.querySelector('#refresh-btn'),
        shareBtn: container.querySelector('#share-btn'),
        autoRefreshCheckbox: container.querySelector('#auto-refresh-checkbox')
    };

    // Generate weather function
    const generateWeather = (cityKey) => {
        const data = appScope.weatherData[cityKey];
        if (!data) return null;

        const tempVariation = Math.floor(Math.random() * 10) - 5; // ±5 degrees
        const temperature = data.baseTemp + tempVariation;
        const condition = data.conditions[Math.floor(Math.random() * data.conditions.length)];
        const humidity = Math.floor(Math.random() * (data.humidity[1] - data.humidity[0])) + data.humidity[0];
        const windSpeed = Math.floor(Math.random() * (data.windSpeed[1] - data.windSpeed[0])) + data.windSpeed[0];
        const pressure = Math.floor(Math.random() * (data.pressure[1] - data.pressure[0])) + data.pressure[0];

        return {
            city: data.city,
            country: data.country,
            temperature,
            condition,
            humidity,
            windSpeed,
            pressure,
            icon: data.icon,
            lastUpdated: new Date()
        };
    };

    // Show weather function
    const showWeather = () => {
        const selectedCity = appScope.elements.citySelect.value;
        if (!selectedCity) {
            appScope.elements.weatherDisplay.innerHTML = '<div class="error">Please select a city first!</div>';
            return;
        }

        appScope.elements.weatherDisplay.innerHTML = '<div class="loading">🌤️ Loading weather data...</div>';

        // Simulate API delay
        setTimeout(() => {
            const weather = generateWeather(selectedCity);
            if (!weather) {
                appScope.elements.weatherDisplay.innerHTML = '<div class="error">Failed to load weather data</div>';
                return;
            }

            appScope.currentCity = selectedCity;

            appScope.elements.weatherDisplay.innerHTML = `
                <div class="weather-card">
                    <div class="weather-icon">${weather.icon}</div>
                    <div class="weather-city">${weather.city}, ${weather.country}</div>
                    <div class="weather-temp">${weather.temperature}°C</div>
                    <div class="weather-desc">${weather.condition}</div>
                    <div class="weather-details">
                        <div class="weather-detail">
                            <strong>Humidity</strong>
                            ${weather.humidity}%
                        </div>
                        <div class="weather-detail">
                            <strong>Wind</strong>
                            ${weather.windSpeed} km/h
                        </div>
                        <div class="weather-detail">
                            <strong>Pressure</strong>
                            ${weather.pressure} hPa
                        </div>
                        <div class="weather-detail">
                            <strong>Feels like</strong>
                            ${weather.temperature + Math.floor(Math.random() * 6) - 3}°C
                        </div>
                    </div>
                    <div class="last-updated">
                        Last updated: ${weather.lastUpdated.toLocaleTimeString()}
                    </div>
                </div>
            `;
        }, 800);
    };

    // Refresh current weather
    const refreshWeather = () => {
        if (appScope.currentCity) {
            showWeather();
        }
    };

    // Share weather function
    const shareWeather = () => {
        if (!appScope.currentCity) {
            alert('No weather data to share!');
            return;
        }

        const cityData = appScope.weatherData[appScope.currentCity];
        const shareText = `Current weather in ${cityData.city}: Check out this weather app!`;

        if (navigator.share) {
            navigator.share({
                title: 'Weather Update',
                text: shareText,
                url: window.location.href
            });
        } else {
            // Fallback to clipboard
            navigator.clipboard.writeText(shareText).then(() => {
                alert('Weather info copied to clipboard!');
            }).catch(() => {
                alert(`Weather info: ${shareText}`);
            });
        }
    };

    // Auto-refresh functionality
    const toggleAutoRefresh = () => {
        if (appScope.elements.autoRefreshCheckbox.checked) {
            appScope.refreshInterval = setInterval(() => {
                if (appScope.currentCity) {
                    refreshWeather();
                }
            }, 30000); // 30 seconds
        } else {
            if (appScope.refreshInterval) {
                clearInterval(appScope.refreshInterval);
                appScope.refreshInterval = null;
            }
        }
    };

    // Event handlers
    const handleCityChange = () => {
        if (appScope.elements.citySelect.value) {
            showWeather();
        }
    };

    // Bind events
    appScope.elements.getWeatherBtn.addEventListener('click', showWeather);
    appScope.elements.citySelect.addEventListener('change', handleCityChange);
    appScope.elements.refreshBtn.addEventListener('click', refreshWeather);
    appScope.elements.shareBtn.addEventListener('click', shareWeather);
    appScope.elements.autoRefreshCheckbox.addEventListener('change', toggleAutoRefresh);

    // Store cleanup functions
    appScope.cleanup.push(() => {
        if (appScope.refreshInterval) {
            clearInterval(appScope.refreshInterval);
        }
        appScope.elements.getWeatherBtn.removeEventListener('click', showWeather);
        appScope.elements.citySelect.removeEventListener('change', handleCityChange);
        appScope.elements.refreshBtn.removeEventListener('click', refreshWeather);
        appScope.elements.shareBtn.removeEventListener('click', shareWeather);
        appScope.elements.autoRefreshCheckbox.removeEventListener('change', toggleAutoRefresh);
    });

    // Return module interface
    return {
        // Public API
        getCurrentWeather: () => appScope.currentCity ? generateWeather(appScope.currentCity) : null,
        setCity: (cityKey) => {
            if (appScope.weatherData[cityKey]) {
                appScope.elements.citySelect.value = cityKey;
                showWeather();
            }
        },
        refreshWeather,
        getAvailableCities: () => Object.keys(appScope.weatherData),

        // Cleanup function
        cleanup: () => {
            console.log('Cleaning up Weather App Module');
            appScope.cleanup.forEach(fn => fn());
            container.innerHTML = '';
        }
    };
}