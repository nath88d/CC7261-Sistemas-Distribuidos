function salvarUsuarioLogado(nome) {
    localStorage.setItem('usuarioLogado', nome);  // Agora só guardamos o nome do usuário
}

function getUsuarioLogado() {
    return localStorage.getItem('usuarioLogado');  // Retorna o nome do usuário logado
}

function getUsuarioNome() {
    return localStorage.getItem('usuarioLogado');  // Aqui também, retornamos o nome do usuário
}
