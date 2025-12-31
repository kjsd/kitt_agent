# About
This repository contains the implementation of the KittAgent modules which are
resposibility of management of the AI agent platform for advanced physical operations.
See README.md for more infomations.

# 開発環境
Dockerで開発する．環境定義は./Dockerfile，./docker-compose.ymlにある．
デフォルトではMIX_ENV=devなので，テストのときは次のようにする．
- `docker compose run --rm -e MIX_ENV=test app mix test`

# 本番環境
このPCが本番環境である．Docker + PostgreSQL環境がセットアップされている．
本番用のイメージは./rel/overlays/Dockerfileで作成される．
実行時は./rel/overlays/kitt-agent.ymlを使う．
GitHubのmainブランチにマージすると自動的に本番イメージがDockerHubにpushされる．
