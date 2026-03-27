import TodoItem from './TodoItem'

export default function TodoList({ todos, onToggle, onDelete }) {
  if (todos.length === 0) {
    return <p style={styles.empty}>Todoがありません。上から追加してください！</p>
  }

  const remaining = todos.filter((t) => !t.completed).length

  return (
    <div>
      <p style={styles.count}>
        残り <strong>{remaining}</strong> / {todos.length} 件
      </p>
      <ul style={{ padding: 0 }}>
        {todos.map((todo) => (
          <TodoItem key={todo.id} todo={todo} onToggle={onToggle} onDelete={onDelete} />
        ))}
      </ul>
    </div>
  )
}

const styles = {
  empty: {
    textAlign: 'center',
    color: '#94a3b8',
    padding: '40px 0',
    fontSize: '15px',
  },
  count: {
    fontSize: '14px',
    color: '#64748b',
    marginBottom: '12px',
  },
}
