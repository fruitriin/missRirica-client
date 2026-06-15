import './style.css'

interface Todo {
  id: number;
  text: string;
  done: boolean;
}

let todos: Todo[] = [];
let nextId = 1;

function renderTodos() {
  const todoList = document.querySelector<HTMLUListElement>('#todo-list')!;
  todoList.innerHTML = todos.map(todo => `
    <li>
      <input type="checkbox" ${todo.done ? 'checked' : ''} data-id="${todo.id}" />
      <span style="${todo.done ? 'text-decoration: line-through' : ''}">${todo.text}</span>
      <button data-delete="${todo.id}">Delete</button>
    </li>
  `).join('');
}

document.querySelector<HTMLDivElement>('#app')!.innerHTML = `
  <div>
    <h1>App Version 2 - Todo List</h1>
    <div class="card">
      <input type="text" id="todo-input" placeholder="Enter a new todo" />
      <button id="add-todo">Add Todo</button>
      <ul id="todo-list"></ul>
    </div>
    <p>Simple todo app - Version 2.0.0</p>
  </div>
`

const input = document.querySelector<HTMLInputElement>('#todo-input')!;
const addBtn = document.querySelector<HTMLButtonElement>('#add-todo')!;
const todoList = document.querySelector<HTMLUListElement>('#todo-list')!;

addBtn.addEventListener('click', () => {
  const text = input.value.trim();
  if (text) {
    todos.push({ id: nextId++, text, done: false });
    input.value = '';
    renderTodos();
  }
});

todoList.addEventListener('change', (e) => {
  const target = e.target as HTMLInputElement;
  if (target.type === 'checkbox') {
    const id = parseInt(target.dataset.id!);
    const todo = todos.find(t => t.id === id);
    if (todo) {
      todo.done = target.checked;
      renderTodos();
    }
  }
});

todoList.addEventListener('click', (e) => {
  const target = e.target as HTMLElement;
  if (target.dataset.delete) {
    const id = parseInt(target.dataset.delete);
    todos = todos.filter(t => t.id !== id);
    renderTodos();
  }
});
