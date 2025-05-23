from pydantic import BaseModel
from typing import List, Optional

# Classe para o Usuario
class Usuario(BaseModel):
    nome: str
    seguidores: List[str] = []  # Lista de IDs de seguidores
    seguindo: List[str] = []  # Lista de IDs de quem o usuário está seguindo
    postagens: List[str] = []  # Lista de IDs de postagens feitas pelo usuário
    mensagens_privadas: List[str] = []  # Lista de IDs de mensagens privadas

    class Config:
        # A configuração pode ser ajustada caso haja algum outro comportamento específico
        orm_mode = True  # Permite conversão de objetos para dict

# Classe para a Postagem
class Postagem(BaseModel):
    usuario_id: str  # ID do usuário que criou a postagem
    texto: str  # Conteúdo da postagem
    post_id: Optional[str] = None  # ID da postagem (opcional, pode ser gerado ao criar)
    timestamp: Optional[str] = None  # Timestamp opcional para quando a postagem foi feita

# Classe para Mensagem Privada
class Mensagem(BaseModel):
    de: str  # ID do usuário que enviou a mensagem
    para: str  # ID do usuário que recebeu a mensagem
    texto: str  # Conteúdo da mensagem
    id_mensagem: Optional[str] = None  # ID da mensagem
    timestamp: Optional[str] = None  # Timestamp opcional para quando a mensagem foi enviada
