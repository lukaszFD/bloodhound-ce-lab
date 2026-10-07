# Rola `app` (do uzupełnienia)

Miejsce na własną rolę wdrażającą aplikację na przygotowanym hoście z Podmanem.

Sugerowany układ:

```
roles/app/
├── defaults/main.yml
├── tasks/main.yml        # numeracja tasków od [03.x.x]
└── templates/
```

Po dodaniu roli odkomentuj ją w `site.yml`.

Do uruchamiania stacków z plików compose pod Podmanem masz dwie drogi:

- `podman-compose` (zainstalowany przez rolę `podman`) — wywoływany np. przez `ansible.builtin.command`,
- `docker compose` / `community.docker.docker_compose_v2` przez socket Podmana — wymaga ustawienia
  `DOCKER_HOST=unix:///run/podman/podman.sock` oraz pluginu `docker-compose` na hoście.
