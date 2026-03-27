export default function TodoItem({ todo, onToggle, onDelete }) {
  return (
    <li style={styles.item}>
      <input
        type="checkbox"
        checked={todo.completed}
        onChange={() => onToggle(todo.id, !todo.completed)}
        style={styles.checkbox}
      />
      <span style={{ ...styles.title, ...(todo.completed ? styles.completed : {}) }}>
        {todo.title}
      </span>
      <button
        onClick={() => onDelete(todo.id)}
        style={styles.deleteBtn}
        aria-label="削除"
      >
        ✕
      </button>
    </li>
  )
}

const styles = {
  item: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
    padding: '14px 16px',
    background: '#fff',
    borderRadius: '8px',
    marginBottom: '8px',
    boxShadow: '0 1px 3px rgba(0,0,0,0.07)',
    listStyle: 'none',
  },
  checkbox: {
    width: '18px',
    height: '18px',
    cursor: 'pointer',
    accentColor: '#4f46e5',
    flexShrink: 0,
  },
  title: {
    flex: 1,
    fontSize: '16px',
  },
  completed: {
    textDecoration: 'line-through',
    color: '#94a3b8',
  },
  deleteBtn: {
    background: 'none',
    border: 'none',
    color: '#94a3b8',
    fontSize: '16px',
    cursor: 'pointer',
    padding: '4px 8px',
    borderRadius: '4px',
    transition: 'color 0.2s',
  },
}
