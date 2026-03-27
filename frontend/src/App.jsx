import { useState, useEffect } from 'react'
import AddTodo from './components/AddTodo'
import TodoList from './components/TodoList'
import { fetchTodos, createTodo, updateTodo, deleteTodo } from './api'

export default function App() {
  const [todos, setTodos] = useState([])
  const [error, setError] = useState(null)
  const [loading, setLoading] = useState(true)

  // 初回ロード時にTodo一覧を取得
  useEffect(() => {
    fetchTodos()
      .then(setTodos)
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false))
  }, [])

  async function handleAdd(title) {
    try {
      const newTodo = await createTodo(title)
      setTodos((prev) => [newTodo, ...prev])
    } catch (e) {
      setError(e.message)
    }
  }

  async function handleToggle(id, completed) {
    try {
      const updated = await updateTodo(id, { completed })
      setTodos((prev) => prev.map((t) => (t.id === id ? updated : t)))
    } catch (e) {
      setError(e.message)
    }
  }

  async function handleDelete(id) {
    try {
      await deleteTodo(id)
      setTodos((prev) => prev.filter((t) => t.id !== id))
    } catch (e) {
      setError(e.message)
    }
  }

  return (
    <div style={styles.container}>
      <div style={styles.card}>
        <h1 style={styles.title}>Todo App</h1>

        {error && (
          <div style={styles.error}>
            {error}
            <button onClick={() => setError(null)} style={styles.errorClose}>✕</button>
          </div>
        )}

        <AddTodo onAdd={handleAdd} />

        {loading ? (
          <p style={styles.loading}>読み込み中...</p>
        ) : (
          <TodoList todos={todos} onToggle={handleToggle} onDelete={handleDelete} />
        )}
      </div>
    </div>
  )
}

const styles = {
  container: {
    minHeight: '100vh',
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'flex-start',
    padding: '60px 16px',
    background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
  },
  card: {
    background: '#f8fafc',
    borderRadius: '16px',
    padding: '32px',
    width: '100%',
    maxWidth: '560px',
    boxShadow: '0 20px 60px rgba(0,0,0,0.2)',
  },
  title: {
    fontSize: '28px',
    fontWeight: '700',
    marginBottom: '24px',
    color: '#1e293b',
  },
  error: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    background: '#fee2e2',
    color: '#dc2626',
    padding: '12px 16px',
    borderRadius: '8px',
    marginBottom: '16px',
    fontSize: '14px',
  },
  errorClose: {
    background: 'none',
    border: 'none',
    color: '#dc2626',
    cursor: 'pointer',
    fontSize: '16px',
  },
  loading: {
    textAlign: 'center',
    color: '#94a3b8',
    padding: '40px 0',
  },
}
