document.addEventListener('DOMContentLoaded', async () => {
    const nomeLogado = getUsuarioLogado(); // Busca o nome de usuário logado
    if (!nomeLogado) {
        window.location.href = "index.html"; // Se não estiver logado, redireciona para a página de login
        return;
    }

    document.getElementById('usuarioNome').textContent = nomeLogado;

    // Busca o ID do usuário logado
    const usuariosRes = await fetch('http://127.0.0.1:8000/usuarios/');
    const usuarios = await usuariosRes.json();
    console.log("Usuarios", usuarios)
    const usuarioLogado = usuarios.find(u => u.nome === nomeLogado); // Busca pelo nome do usuário
    console.log("Conteudo do usuario logado", usuarioLogado);
    const usuarioId = usuarioLogado ? usuarioLogado.nome : "Desconhecido";  // Nome do usuário
    console.log("UsuarioId consteudo: ", usuarioId)

    // Postagem
    document.getElementById('postForm').addEventListener('submit', async function (e) {
        e.preventDefault();

        const texto = document.getElementById('textoPost').value;

        await fetch('http://127.0.0.1:8000/postagens/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ usuario_id: usuarioId, texto })
        });

        document.getElementById('textoPost').value = "";
        carregarPostagens();
    });

    // Mensagem privada
    document.getElementById('mensagemForm').addEventListener('submit', async function (e) {
        e.preventDefault();

        const para = document.getElementById('destinatario').value; // Nome do destinatário
        const texto = document.getElementById('textoMsg').value;

        await fetch('http://127.0.0.1:8000/mensagens/', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ de: nomeLogado, para, texto }) // Usando o nome do usuário logado
        });

        alert("Mensagem enviada!");
        document.getElementById('textoMsg').value = "";
    });

    // Carregar postagens
    async function carregarPostagens() {
        const res = await fetch('http://127.0.0.1:8000/postagens/');
        const postagens = await res.json();
        console.log("Postagens", postagens);
        const ul = document.getElementById('postagensLista');
        ul.innerHTML = "";

        postagens.forEach(p => {
            const li = document.createElement('li');
            li.textContent = `${p.usuario_id}: ${p.texto}`;  // Exibe o nome do usuário
            console.log("Saida", p.usuario_id);
            ul.appendChild(li);
        });
    }

    carregarPostagens();

});

// Trocar entre abas
function mostrarAba(nome) {
    document.querySelectorAll('.aba').forEach(div => div.style.display = 'none');
    document.getElementById(`aba-${nome}`).style.display = 'block';

    if (nome === 'conversas') {
        carregarConversas();
    }
}

async function carregarConversas() {
    const res = await fetch('http://127.0.0.1:8000/mensagens/');
    const todasMensagens = await res.json();

    const nomeLogado = getUsuarioLogado();  // Usando nomeLogado em vez de email

    const minhasMensagens = todasMensagens.filter(m =>
        m.de === nomeLogado || m.para === nomeLogado  // Filtra mensagens usando nome do usuário
    );

    const contatos = new Set();
    minhasMensagens.forEach(m => {
        const outro = m.de === nomeLogado ? m.para : m.de;
        contatos.add(outro);
    });

    const lista = document.getElementById('listaConversas');
    lista.innerHTML = "";

    contatos.forEach(nomeContato => {
        const btn = document.createElement('button');
        btn.textContent = `Ver conversa com ${nomeContato}`;
        btn.onclick = () => mostrarHistorico(nomeContato, minhasMensagens);
        lista.appendChild(btn);
    });
}

function mostrarHistorico(contato, mensagens) {
    const nomeLogado = getUsuarioLogado();  // Usando o nome do usuário logado
    const ul = document.getElementById('historicoConversa');
    const titulo = document.getElementById('tituloConversa');
    titulo.textContent = `Conversa com ${contato}`;
    ul.innerHTML = "";

    const historico = mensagens.filter(m =>
        (m.de === nomeLogado && m.para === contato) ||
        (m.de === contato && m.para === nomeLogado)
    );

    historico.forEach(m => {
        const li = document.createElement('li');
        li.textContent = `${m.de}: ${m.texto}`;  // Exibe o nome do usuário nas mensagens
        ul.appendChild(li);
    });
}


///////////////////////////////////////////////////////////////////////////

document.getElementById('seguirForm').addEventListener('submit', async function (e) {
    e.preventDefault();

    const seguirNome = document.getElementById('seguirNome').value;
    const meuNome = getUsuarioLogado();

    const res = await fetch('http://127.0.0.1:8000/seguir/?usuario_a=' + meuNome + '&usuario_b=' + seguirNome, {
        method: 'POST'
    });

    if (res.ok) {
        alert(`Agora você segue ${seguirNome}`);
        document.getElementById('seguirNome').value = "";
    } else {
        alert("Erro ao seguir.");
    }
});
