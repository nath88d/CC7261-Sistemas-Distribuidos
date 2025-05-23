import asyncio
import json
from fastapi import FastAPI, HTTPException, Body
from models import Usuario, Postagem, Mensagem
import aio_pika
from typing import List
from datetime import datetime
from fastapi.middleware.cors import CORSMiddleware
import subprocess

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

async def executar_bind_periodicamente(intervalo: int = 30):
    while True:
        print("Executando bind_queues.py...")
        subprocess.run(["python3", "bind_queues.py"])
        await asyncio.sleep(intervalo)


class Broker:
    def __init__(self):
        self.connection = None
        self.channel = None
        self.response_queue = None
        self.responses = {}
        self.loop = asyncio.get_event_loop()

    async def connect(self):
        for attempt in range(10):
            try:
                self.connection = await aio_pika.connect_robust("amqp://guest:guest@rabbitmq:5672/")
                self.channel = await self.connection.channel()
                self.response_queue = await self.channel.declare_queue(exclusive=True)
                await self.response_queue.consume(self.on_response)
                print("RabbitMQ sucesso")
                return
            except Exception as e:
                print(f"Ocorreu um erro – Aguardando resposta RabbitMQ... Tentativas {attempt+1}/10")
                await asyncio.sleep(2)
        raise Exception("Falha ao conectar ao RabbitMQ")

    async def disconnect(self):
        await self.connection.close() 

    async def on_response(self, message: aio_pika.IncomingMessage):
        async with message.process():
            correlation_id = message.correlation_id
            if correlation_id in self.responses:
                self.responses[correlation_id].set_result(message.body.decode())

    async def rpc_publish(self, queue_name, message, correlation_id):
        self.responses[correlation_id] = self.loop.create_future()

        await self.channel.default_exchange.publish(
            aio_pika.Message(
                body=json.dumps(message).encode(),
                correlation_id=correlation_id,
                reply_to=self.response_queue.name,
            ),
            routing_key=queue_name,
        )

        response = await self.responses[correlation_id]
        del self.responses[correlation_id]
        return response

broker = Broker()

@app.on_event("startup")
async def startup():
    await broker.connect()
    asyncio.create_task(executar_bind_periodicamente(1))
@app.on_event("shutdown")
async def shutdown():
    await broker.disconnect()

def add_timestamp(data: dict):
    data["timestamp"] = datetime.utcnow().isoformat()
    return data

@app.post("/usuarios/")
async def criar_usuario(usuario: dict = Body(...)):
    nome = usuario["nome"]
    novo_usuario = Usuario(
        nome=nome,
        seguidores=[],
        seguindo=[],
        postagens=[],
        mensagens_privadas=[]
    )
    print(f"Usuário criado: {novo_usuario}")

    message = {"operation": "create_user", "data": novo_usuario.dict()}
    correlation_id = nome

    response = await broker.rpc_publish("task_queue", message, correlation_id)
    return {"mensagem": "Usuário criado", "usuario": novo_usuario, "response": response}

@app.post("/postagens/")
async def criar_postagem(postagem: Postagem):
    postagem_data = postagem.dict()
    postagem_data["post_id"] = f"post_{int(datetime.utcnow().timestamp())}"
    postagem_data = add_timestamp(postagem_data)

    print(f"Postagem criada: {postagem_data}")

    message = {"operation": "create_post", "data": postagem_data}
    correlation_id = postagem_data["post_id"]

    response = await broker.rpc_publish("task_queue", message, correlation_id)
    return {"mensagem": "Postagem criada", "postagem": postagem_data, "response": response}

@app.post("/mensagens/")
async def enviar_mensagem(mensagem: Mensagem):
    mensagem_data = mensagem.dict()
    mensagem_data = add_timestamp(mensagem_data)
    mensagem_data["id_mensagem"] = f"msg_{int(datetime.utcnow().timestamp())}"

    print(f"Mensagem enviada: {mensagem_data}")

    message = {"operation": "send_message", "data": mensagem_data}
    correlation_id = mensagem_data["id_mensagem"]

    response = await broker.rpc_publish("task_queue", message, correlation_id)
    return {"mensagem": "Mensagem enviada", "mensagem": mensagem_data, "response": response}

@app.post("/seguir/")
async def seguir(usuario_a: str, usuario_b: str):
    print(f"{usuario_a} agora segue {usuario_b}")

    follow_data = {"follower": usuario_a, "following": usuario_b}
    message = {"operation": "follow", "data": follow_data}
    correlation_id = f"follow_{usuario_a}_{usuario_b}"

    response = await broker.rpc_publish("task_queue", message, correlation_id)
    return {"mensagem": f"{usuario_a} agora segue {usuario_b}", "response": response}

@app.get("/usuarios/")
async def listar_usuarios():
    message = {"operation": "get_users"}
    correlation_id = "listar_usuarios"
    print("Requisitando ao servidor")
    response = await broker.rpc_publish("task_queue", message, correlation_id)
    # print("Retornado: ", response)
    try:
        # print("TRY ")
        usuarios = json.loads(response)
        # print(usuarios)
    except:
        usuarios = []
    return usuarios

@app.get("/postagens/")
async def listar_postagens():
    message = {"operation": "get_posts"}
    correlation_id = "listar_postagens"
    response = await broker.rpc_publish("task_queue", message, correlation_id)
    print("Postagens: ", response)
    try:
        postagens = json.loads(response)
    except:
        postagens = []
    return postagens

@app.get("/mensagens/")
async def listar_mensagens():
    message = {"operation": "get_messages"}
    correlation_id = "listar_mensagens"

    response = await broker.rpc_publish("task_queue", message, correlation_id)
    try:
        mensagens = json.loads(response)
    except:
        mensagens = []
    return mensagens
