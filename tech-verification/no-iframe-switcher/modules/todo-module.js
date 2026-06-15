/**
 * Todo App Module - Exported as a reusable module
 */

export function createTodoApp(container) {
    console.log('Initializing Todo App Module');

    // Create isolated scope
    const appScope = {
        todos: [],
        nextId: 1,
        elements: {},
        cleanup: []
    };

    const styles = `
        .todo-module {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
            background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%);
            border-radius: 10px;
            box-shadow: 0 8px 16px rgba(0,0,0,0.1);
        }
        .todo-module h2 {
            color: white;
            text-align: center;
            margin-top: 0;
            text-shadow: 1px 1px 2px rgba(0,0,0,0.2);
        }
        .todo-input-section {
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
            background: rgba(255,255,255,0.1);
            padding: 15px;
            border-radius: 8px;
            backdrop-filter: blur(10px);
        }
        .todo-input-section input {
            flex: 1;
            padding: 12px;
            border: 2px solid rgba(255,255,255,0.3);
            border-radius: 6px;
            font-size: 16px;
            background: rgba(255,255,255,0.9);
            transition: all 0.3s ease;
        }
        .todo-input-section input:focus {
            outline: none;
            border-color: rgba(255,255,255,0.6);
            background: white;
        }
        .todo-input-section button {
            padding: 12px 20px;
            background: rgba(255,255,255,0.2);
            color: white;
            border: 2px solid rgba(255,255,255,0.3);
            border-radius: 6px;
            cursor: pointer;
            font-weight: bold;
            transition: all 0.3s ease;
        }
        .todo-input-section button:hover {
            background: rgba(255,255,255,0.3);
            transform: translateY(-1px);
        }
        .todo-list {
            list-style: none;
            padding: 0;
            max-height: 400px;
            overflow-y: auto;
        }
        .todo-item {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 12px;
            background: rgba(255,255,255,0.9);
            border-radius: 8px;
            margin-bottom: 8px;
            transition: all 0.3s ease;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .todo-item:hover {
            transform: translateY(-1px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.15);
        }
        .todo-item.completed {
            opacity: 0.7;
            background: rgba(255,255,255,0.6);
        }
        .todo-item.completed .todo-text {
            text-decoration: line-through;
        }
        .todo-checkbox {
            width: 18px;
            height: 18px;
            cursor: pointer;
        }
        .todo-text {
            flex: 1;
            font-size: 16px;
            color: #333;
        }
        .todo-actions {
            display: flex;
            gap: 8px;
        }
        .delete-btn, .edit-btn {
            padding: 6px 12px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 12px;
            font-weight: bold;
            transition: all 0.3s ease;
        }
        .delete-btn {
            background: #ff6b6b;
            color: white;
        }
        .delete-btn:hover {
            background: #ff5252;
        }
        .edit-btn {
            background: #4ecdc4;
            color: white;
        }
        .edit-btn:hover {
            background: #26a69a;
        }
        .todo-stats {
            display: flex;
            justify-content: space-between;
            margin-top: 15px;
            padding: 10px;
            background: rgba(255,255,255,0.1);
            border-radius: 6px;
            color: white;
            font-size: 14px;
        }
        .edit-input {
            flex: 1;
            padding: 8px;
            border: 2px solid #4ecdc4;
            border-radius: 4px;
            font-size: 16px;
        }
        .edit-input:focus {
            outline: none;
            border-color: #26a69a;
        }
    `;

    const html = `
        <div class="todo-module">
            <h2>📝 Todo List Module v2.0.0</h2>
            <div class="todo-input-section">
                <input type="text" id="todo-input" placeholder="What needs to be done?" maxlength="100">
                <button id="add-btn">Add Todo</button>
            </div>
            <ul class="todo-list" id="todo-list"></ul>
            <div class="todo-stats" id="todo-stats">
                <span>Total: 0</span>
                <span>Completed: 0</span>
                <span>Remaining: 0</span>
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
        input: container.querySelector('#todo-input'),
        addBtn: container.querySelector('#add-btn'),
        list: container.querySelector('#todo-list'),
        stats: container.querySelector('#todo-stats')
    };

    // Render todos function
    const renderTodos = () => {
        appScope.elements.list.innerHTML = '';

        appScope.todos.forEach(todo => {
            const li = document.createElement('li');
            li.className = `todo-item ${todo.completed ? 'completed' : ''}`;
            li.dataset.id = todo.id;

            if (todo.editing) {
                li.innerHTML = `
                    <input type="checkbox" class="todo-checkbox" ${todo.completed ? 'checked' : ''}>
                    <input type="text" class="edit-input" value="${todo.text}" maxlength="100">
                    <div class="todo-actions">
                        <button class="edit-btn save-btn">Save</button>
                        <button class="delete-btn cancel-btn">Cancel</button>
                    </div>
                `;
            } else {
                li.innerHTML = `
                    <input type="checkbox" class="todo-checkbox" ${todo.completed ? 'checked' : ''}>
                    <span class="todo-text">${todo.text}</span>
                    <div class="todo-actions">
                        <button class="edit-btn">Edit</button>
                        <button class="delete-btn">Delete</button>
                    </div>
                `;
            }

            appScope.elements.list.appendChild(li);
        });

        updateStats();
    };

    // Update statistics
    const updateStats = () => {
        const total = appScope.todos.length;
        const completed = appScope.todos.filter(t => t.completed).length;
        const remaining = total - completed;

        appScope.elements.stats.innerHTML = `
            <span>Total: ${total}</span>
            <span>Completed: ${completed}</span>
            <span>Remaining: ${remaining}</span>
        `;
    };

    // Add todo function
    const addTodo = () => {
        const text = appScope.elements.input.value.trim();
        if (text) {
            appScope.todos.push({
                id: appScope.nextId++,
                text: text,
                completed: false,
                editing: false,
                createdAt: new Date()
            });
            appScope.elements.input.value = '';
            renderTodos();
        }
    };

    // Toggle todo completion
    const toggleTodo = (id) => {
        const todo = appScope.todos.find(t => t.id === id);
        if (todo) {
            todo.completed = !todo.completed;
            renderTodos();
        }
    };

    // Delete todo
    const deleteTodo = (id) => {
        appScope.todos = appScope.todos.filter(t => t.id !== id);
        renderTodos();
    };

    // Edit todo
    const editTodo = (id) => {
        appScope.todos.forEach(t => t.editing = false); // Close other edits
        const todo = appScope.todos.find(t => t.id === id);
        if (todo) {
            todo.editing = true;
            renderTodos();
            // Focus the edit input
            setTimeout(() => {
                const editInput = container.querySelector('.edit-input');
                if (editInput) {
                    editInput.focus();
                    editInput.select();
                }
            }, 0);
        }
    };

    // Save todo edit
    const saveTodoEdit = (id, newText) => {
        const todo = appScope.todos.find(t => t.id === id);
        if (todo && newText.trim()) {
            todo.text = newText.trim();
            todo.editing = false;
            renderTodos();
        }
    };

    // Cancel todo edit
    const cancelTodoEdit = (id) => {
        const todo = appScope.todos.find(t => t.id === id);
        if (todo) {
            todo.editing = false;
            renderTodos();
        }
    };

    // Event delegation for todo list
    const handleListClick = (event) => {
        const todoItem = event.target.closest('.todo-item');
        if (!todoItem) return;

        const id = parseInt(todoItem.dataset.id);

        if (event.target.classList.contains('todo-checkbox')) {
            toggleTodo(id);
        } else if (event.target.classList.contains('delete-btn')) {
            deleteTodo(id);
        } else if (event.target.classList.contains('edit-btn')) {
            editTodo(id);
        } else if (event.target.classList.contains('save-btn')) {
            const editInput = todoItem.querySelector('.edit-input');
            saveTodoEdit(id, editInput.value);
        } else if (event.target.classList.contains('cancel-btn')) {
            cancelTodoEdit(id);
        }
    };

    // Handle input events
    const handleInputKeyPress = (event) => {
        if (event.key === 'Enter') {
            addTodo();
        }
    };

    const handleEditKeyPress = (event) => {
        if (event.key === 'Enter') {
            const todoItem = event.target.closest('.todo-item');
            const id = parseInt(todoItem.dataset.id);
            saveTodoEdit(id, event.target.value);
        } else if (event.key === 'Escape') {
            const todoItem = event.target.closest('.todo-item');
            const id = parseInt(todoItem.dataset.id);
            cancelTodoEdit(id);
        }
    };

    // Global key handler for edit inputs
    const handleGlobalKeyPress = (event) => {
        if (event.target.classList.contains('edit-input')) {
            handleEditKeyPress(event);
        }
    };

    // Bind events
    appScope.elements.addBtn.addEventListener('click', addTodo);
    appScope.elements.input.addEventListener('keypress', handleInputKeyPress);
    appScope.elements.list.addEventListener('click', handleListClick);
    document.addEventListener('keypress', handleGlobalKeyPress);

    // Store cleanup functions
    appScope.cleanup.push(() => {
        appScope.elements.addBtn.removeEventListener('click', addTodo);
        appScope.elements.input.removeEventListener('keypress', handleInputKeyPress);
        appScope.elements.list.removeEventListener('click', handleListClick);
        document.removeEventListener('keypress', handleGlobalKeyPress);
    });

    // Initial render
    renderTodos();

    // Return module interface
    return {
        // Public API
        getTodos: () => [...appScope.todos],
        addTodo: (text) => {
            if (text && text.trim()) {
                appScope.todos.push({
                    id: appScope.nextId++,
                    text: text.trim(),
                    completed: false,
                    editing: false,
                    createdAt: new Date()
                });
                renderTodos();
            }
        },
        clearCompleted: () => {
            appScope.todos = appScope.todos.filter(t => !t.completed);
            renderTodos();
        },
        toggleAll: () => {
            const allCompleted = appScope.todos.every(t => t.completed);
            appScope.todos.forEach(t => t.completed = !allCompleted);
            renderTodos();
        },

        // Cleanup function
        cleanup: () => {
            console.log('Cleaning up Todo App Module');
            appScope.cleanup.forEach(fn => fn());
            container.innerHTML = '';
        }
    };
}