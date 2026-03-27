import { useState } from 'react'

export default function AddTodo({ onAdd }) {
  const [title, setTitle] = useState('')
  const [loading, setLoading] = useState(false)

  async function handleSubmit(e) {
    e.preventDefault()
    const trimmed = title.trim()
    if (!trimmed) return

    setLoading(true)
    await onAdd(trimmed)
    setTitle('')
    setLoading(false)
  }

  return (
    <form onSubmit={handleSubmit} style={styles.form}>
      <input
        type="text"
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder="新しいTodoを入力..."
        disabled={loading}
        style={styles.input}
      />
      <button type="submit" disabled={loading || !title.trim()} style={styles.button}>
        {loading ? '追加中...' : '追加'}
      </button>
    </form>
  )
}

const styles = {
  form: {
    display: 'flex',
    gap: '8px',
    marginBottom: '24px',
  },
  input: {
    flex: 1,
    padding: '12px 16px',
    fontSize: '16px',
    border: '2px solid #e2e8f0',
    borderRadius: '8px',
    outline: 'none',
    transition: 'border-color 0.2s',
  },
  button: {
    padding: '12px 24px',
    fontSize: '16px',
    fontWeight: '600',
    background: '#4f46e5',
    color: '#fff',
    border: 'none',
    borderRadius: '8px',
    cursor: 'pointer',
    transition: 'background 0.2s',
  },
}
