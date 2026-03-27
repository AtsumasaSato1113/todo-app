// バックエンドAPIのベースURL
// Docker環境ではvite.config.jsのproxyが /todos → http://backend:8000 に転送する
const BASE_URL = '/todos/'

export async function fetchTodos() {
  const res = await fetch(BASE_URL)
  if (!res.ok) throw new Error('Todoの取得に失敗しました')
  return res.json()
}

export async function createTodo(title) {
  const res = await fetch(BASE_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title }),
  })
  if (!res.ok) throw new Error('Todoの作成に失敗しました')
  return res.json()
}

export async function updateTodo(id, data) {
  const res = await fetch(`${BASE_URL}/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  if (!res.ok) throw new Error('Todoの更新に失敗しました')
  return res.json()
}

export async function deleteTodo(id) {
  const res = await fetch(`${BASE_URL}/${id}`, { method: 'DELETE' })
  if (!res.ok) throw new Error('Todoの削除に失敗しました')
}
