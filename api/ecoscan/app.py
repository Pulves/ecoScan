from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from ecoscan.routes import user, auth


app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # Em produção, substitua pelo domínio real
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(user.router)
app.include_router(auth.router)



@app.get("/")
async def root():
    return {"message": "Hello World"}
