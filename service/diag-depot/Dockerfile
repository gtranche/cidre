# Le service de depot des diagnostics de Cidre (serveur/serveur.mjs), pour le
# Kubernetes de l'equipe (k8s/, README.md). Node seul, aucune dependance npm :
# rien a installer, rien a mettre a jour hors de l'image de base.
#
#   docker buildx build --platform linux/amd64,linux/arm64 -t <registre>/cidre-diag:1.0.0 --push .
FROM node:22.11.0-alpine3.20

ENV NODE_ENV=production \
    PORT=8080 \
    DONNEES=/donnees
WORKDIR /app
COPY depot.js package.json ./
COPY serveur/ ./serveur/
# l'utilisateur « node » (1000) de l'image : jamais root ; le volume lui appartient
RUN mkdir -p /donnees && chown node:node /donnees
USER node
EXPOSE 8080
VOLUME ["/donnees"]
CMD ["node", "serveur/serveur.mjs"]
