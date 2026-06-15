import './style.css'

document.querySelector<HTMLDivElement>('#app')!.innerHTML = `
  <div>
    <h1>App Version 1 - Counter</h1>
    <div class="card">
      <button id="counter" type="button">Count: 0</button>
      <button id="reset" type="button">Reset</button>
    </div>
    <p>Simple counter app - Version 1.0.0</p>
  </div>
`

let count = 0;
const counterBtn = document.querySelector<HTMLButtonElement>('#counter')!;
const resetBtn = document.querySelector<HTMLButtonElement>('#reset')!;

counterBtn.addEventListener('click', () => {
  count++;
  counterBtn.textContent = `Count: ${count}`;
});

resetBtn.addEventListener('click', () => {
  count = 0;
  counterBtn.textContent = `Count: ${count}`;
});
