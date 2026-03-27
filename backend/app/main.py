from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .database import engine, Base
from .routers import todos

# データベーステーブルを自動作成
Base.metadata.create_all(bind=engine)

app = FastAPI(title="Todo API", version="1.0.0")

# CORS設定 (ReactフロントエンドからAPIを呼べるようにする)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(todos.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
