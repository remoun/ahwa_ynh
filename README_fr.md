<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->

# Ahwa pour YunoHost

[Read this in English / Lire en anglais](./README.md)

Paquet YunoHost pour [Ahwa](https://github.com/remoun/ahwa) — salles
de délibération IA privées. Réunissez un petit conseil de personas IA
pour réfléchir à un dilemme qui ne se résout pas en une seule réponse.

Ce dépôt contient uniquement le packaging YNH. Le code de
l'application vit dans le dépôt amont
<https://github.com/remoun/ahwa> ; le script d'installation le clone
au moment de l'installation.

## Installation

En attendant que le paquet rejoigne le catalogue officiel YunoHost,
installez-le directement depuis l'URL GitHub :

```bash
sudo yunohost app install https://github.com/remoun/ahwa_ynh
```

## Ce qu'il vous faut

- Une clé pour un fournisseur LLM, configurée après l'installation
  via l'interface admin YNH ou en éditant `/var/www/ahwa/.env`.
  Voir le
  [guide d'auto-hébergement](https://github.com/remoun/ahwa/blob/main/docs/self-host.md#llm-providers)
  pour le tableau complet des variables d'environnement.
- Environ 300 Mo de disque + 256 Mo de RAM à l'exécution. La
  construction (pendant l'installation) nécessite ~1 Go de RAM
  transitoirement.

## Travailler sur le paquet

Voir [CONTRIBUTING.md](./CONTRIBUTING.md) pour la boucle d'itération
locale (linter, installation VPS en direct, package_check).

## Amont

- Application : <https://github.com/remoun/ahwa>
- Problèmes non spécifiques à YNH :
  <https://github.com/remoun/ahwa/issues>
- Problèmes avec ce paquet :
  <https://github.com/remoun/ahwa_ynh/issues>

Licence : AGPL-3.0-or-later (identique à l'amont).
