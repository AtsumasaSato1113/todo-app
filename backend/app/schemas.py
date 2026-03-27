from pydantic import BaseModel
from datetime import datetime


class TodoBase(BaseModel):
    title: str


class TodoCreate(TodoBase):
    pass


class TodoUpdate(BaseModel):
    title: str | None = None
    completed: bool | None = None


class TodoResponse(TodoBase):
    id: int
    completed: bool
    created_at: datetime

    model_config = {"from_attributes": True}
