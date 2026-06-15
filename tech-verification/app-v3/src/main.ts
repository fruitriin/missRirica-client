import './style.css'

const weatherEmojis: { [key: string]: string } = {
  'Sunny': '☀️',
  'Cloudy': '☁️',
  'Rainy': '🌧️',
  'Snowy': '❄️',
  'Stormy': '⛈️'
};

const weathers = Object.keys(weatherEmojis);
const cities = ['Tokyo', 'New York', 'London', 'Paris', 'Sydney'];

function getRandomWeather() {
  return weathers[Math.floor(Math.random() * weathers.length)];
}

function getRandomTemp() {
  return Math.floor(Math.random() * 30) + 5;
}

document.querySelector<HTMLDivElement>('#app')!.innerHTML = `
  <div>
    <h1>App Version 3 - Weather</h1>
    <div class="card">
      <select id="city-select">
        ${cities.map(city => `<option value="${city}">${city}</option>`).join('')}
      </select>
      <button id="check-weather">Check Weather</button>
      <div id="weather-result" style="margin-top: 20px; font-size: 1.2em;"></div>
    </div>
    <p>Simple weather app - Version 3.0.0</p>
  </div>
`

const citySelect = document.querySelector<HTMLSelectElement>('#city-select')!;
const checkBtn = document.querySelector<HTMLButtonElement>('#check-weather')!;
const resultDiv = document.querySelector<HTMLDivElement>('#weather-result')!;

checkBtn.addEventListener('click', () => {
  const city = citySelect.value;
  const weather = getRandomWeather();
  const temp = getRandomTemp();
  const emoji = weatherEmojis[weather];

  resultDiv.innerHTML = `
    <h3>${city}</h3>
    <p>${emoji} ${weather}</p>
    <p>Temperature: ${temp}°C</p>
  `;
});
