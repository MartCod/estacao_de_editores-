-- Payload no formato que a versão 1 grava (com casos difíceis de propósito).
insert into public.editor_panel_shared_data(id, payload) values (1, $j$
{
  "activeMovieId": "m1", "productionMovieId": "m2", "activeDept": "efeitos",
  "movies": [
    { "id": "m1", "nome": "Filme Um", "caminho51": "X:/legado", "caminho20": "",
      "poster": "data:image/jpeg;base64,QUJD", "drive": "https://drive/um",
      "movieLinks": [
        { "id": "L1", "url": "https://primeiro-link-escondido", "type": "Filmes 5.1", "languages": [{"id":"BR-51","country":"BR","name":"Português (BR) 5.1"}] },
        { "id": "L2", "url": "https://segundo", "idiomas": [], "type": "Mono" }
      ],
      "depts": {
        "vocal": { "editors": [
          { "id": "e1", "nome": "Ana", "user_id": "eeeeeeee-0000-0000-0000-000000000001",
            "idiomas": [
              { "id": "r1", "idioma": "Inglês 5.1", "inicio": "2026-11-01", "entrega": "", "urgencia": "alta", "status": "fazendo", "revisor": "Rev", "statusRevisao": "andamento" },
              { "id": "r2", "idioma": "Francês 2.0", "inicio": "lixo", "entrega": "2026-11-09", "urgencia": "???", "status": "concluido", "revisor": "", "statusRevisao": "revisado" }
            ] },
          { "id": "e2", "nome": "Bruno", "idiomas": [ { "id": "r3", "idioma": "Alemão 5.1" } ] },
          { "id": "e3", "nome": "Duda", "idiomas": [] },
          { "id": "e4", "nome": "Editor 4", "idiomas": ["Russo 5.1", "Turco 2.0"] }
        ] },
        "efeitos": { "editors": [
          { "id": "s1", "nome": "Bruno", "inicio": "2026-11-02", "entrega": "", "urgencia": "baixa", "status": "pendente" },
          { "id": "s2", "nome": "<img src=x onerror=alert(1)>", "inicio": "", "entrega": "", "urgencia": "media", "status": "fazendo" }
        ] },
        "musica": { "editors": [ { "id": "s3", "nome": "Ana", "status": "concluido", "entrega": "2026-10-30" } ] }
      } },
    { "id": "m2", "nome": "Filme Dois", "poster": "data:text/html;base64,PHNjcmlwdD4=",
      "depts": { "vocal": { "editors": [ { "id": "e1", "nome": "Ana", "idiomas": [ { "id": "r1", "idioma": "Japonês 5.1" } ] } ] } } }
  ],
  "completedMovies": [
    { "id": "c1", "nome": "Antigo", "concluidoEm": "2026-10-01T12:00:00.000Z",
      "entries": [ { "idioma": "Inglês 5.1", "editor": "Ana", "revisor": "Rev" } ] },
    { "id": "c2", "nome": "", "concluidoEm": "data ruim", "entries": [] }
  ]
}
$j$);
