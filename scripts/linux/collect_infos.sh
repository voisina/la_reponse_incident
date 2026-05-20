#!/bin/bash

# +------------------------------+
# |  Vérifications préliminaire  |
# +------------------------------+

#  Binaires nécessaires
# -----------------------
for cmd in ssh-keygen ssh-copy-id ssh-agent ssh scp tar; do
  if ! which "$cmd" &> /dev/null; then
    echo "Commande $cmd introuvable, cette dernière est nécessaire pour l'exécution de ce script" >&2
    exit 1
  fi
done

#  Permissions
# -------------
if ! sudo -l tar &> /dev/null; then
  echo "L'utilisateur appelant doit pouvoir exécuter tar comme root" >&2
  exit 2
fi


# +-------------------+
# |  Préparation SSH  |
# +-------------------+

tmp_dir=$(mktemp -d)
key="${tmp_dir}/cle_ssh_temporaire"


#  Création d'une clé ssh temporaire
# -----------------------------------
ssh-keygen -f "$key" -t ecdsa -C "Clé temporaire pour récupérer les informations" -N ""

#  Chargement de l'agent
# -----------------------
eval $(ssh-agent)
ssh-add "$key"

# +------------------------------------------------+
# |  Récupération des données pour tous les hôtes  |
# +------------------------------------------------+
for host in "$@"; do

  #  Préparation de l'arborescence
  # --------------------------------
  machine_id="${host#*@}"
  mkdir -p "results/${machine_id}"

  #  Partage de la clé temporaire
  # -------------------------------
  ssh-copy-id -i "$key" "$host"

  #  Partage du binaire d'extraction
  # ---------------------------------
  scp ./scrap.sh "$host:"
  ssh "$host" 'chmod +x ~/scrap.sh'

  #  Extraction des données
  # -------------------------
  ssh -t "$host" 'sudo bash ~/scrap.sh'

  #  Récupération de l'archive
  # -----------------------------
  scp "$host:/tmp/computer_info.tar.gz" "${machine_id}.tar.gz"
  sudo tar --atime-preserve --same-permissions --same-owner -C "results/${machine_id}" -xf "${machine_id}.tar.gz"

  #  Nettoyage
  # -----------
  ssh "$host" "rm ~/scrap.sh"
  ssh "$host" "sed -i '/ *Clé temporaire pour récupérer les informations *$/d' ~/.ssh/authorized_keys"
done

rm -r "$tmp_dir"
