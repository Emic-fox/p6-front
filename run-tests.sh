#!/usr/bin/env bash
# Exécute les tests unitaires d'un projet en détectant automatiquement son type
# (Gradle ou npm) et publie les rapports JUnit XML dans <projet>/test-results/.
#
# Usage : ./run-tests.sh   (à placer à la racine du projet)
#
# Codes de sortie (cf. https://tldp.org/LDP/abs/html/exitcodes.html : on évite 1-2 et 126-165,
# réservés au shell, et on utilise la plage 64-113 de sysexits.h pour les erreurs du script) :
#   0   tests OK
#   64  dépendance manquante (java, node, npm, gradlew, échec de npm ci)
#   65  type de projet non reconnu
#   66  aucun rapport JUnit produit
#   autre code non nul : code de retour de l'outil de test (Gradle / npm), transmis tel quel

set -uo pipefail

readonly EX_DEPENDENCY=64 # Dépendance manquante
readonly EX_PROJECT=65    # Type de projet non reconnu
readonly EX_NOREPORT=66   # Aucun rapport JUnit produit

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit "$EX_PROJECT"
RESULTS_DIR="$PROJECT_DIR/test-results"

main() {
  log "Projet : $PROJECT_DIR"

  # Nettoyage des artefacts de tests précédents
  rm -rf "$RESULTS_DIR"
  mkdir -p "$RESULTS_DIR"

  # Détection du type de projet et exécution du script associé
  local status
  if [[ -f "$PROJECT_DIR/gradlew" && -f "$PROJECT_DIR/build.gradle" ]]; then
    log "Type détecté : gradle"
    run_gradle_tests; status=$?
  elif [[ -f "$PROJECT_DIR/package.json" ]]; then
    log "Type détecté : npm"
    run_npm_tests; status=$?
  else
    fail "$EX_PROJECT" "Type de projet non reconnu (ni Gradle, ni npm) dans $PROJECT_DIR."
  fi

  # Affichage du résultat
  if [[ $status -eq 0 ]]; then
    log "Tous les tests sont passés."
  else
    log "Échec (code $status)."
  fi
  exit $status
}

log()  {
  echo "[run-tests] $*"
}

fail() {
  local code="$1"
  local message="$2"
  echo "[run-tests] ERREUR : $message" >&2
  exit "$code"
}

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "$EX_DEPENDENCY" "'$1' est introuvable dans le PATH."
  fi
}

# Copie les rapports JUnit XML de $1 vers $RESULTS_DIR.
# Retourne $EX_NOREPORT si aucun rapport n'est trouvé.
copy_reports() {
  local src="$1"
  if [[ ! -d "$src" ]] || [[ -z "$(find "$src" -name '*.xml' -print -quit)" ]]; then
    echo "[run-tests] Aucun rapport JUnit trouvé dans $src" >&2
    return "$EX_NOREPORT"
  fi

  find "$src" -name '*.xml' -exec cp {} "$RESULTS_DIR/" \;
  log "Rapports JUnit copiés dans $RESULTS_DIR"
}

run_gradle_tests() {
  require java
  if [[ ! -f "$PROJECT_DIR/gradlew" ]]; then
    fail "$EX_DEPENDENCY" "gradlew absent de $PROJECT_DIR."
  fi
  chmod +x "$PROJECT_DIR/gradlew" 2>/dev/null

  log "Gradle : ./gradlew clean test"
  ( cd "$PROJECT_DIR" && ./gradlew clean test --no-daemon )
  local status=$?

  # Les rapports sont copiés même en cas d'échec pour que la CI puisse les publier.
  if ! copy_reports "$PROJECT_DIR/build/test-results/test" && [[ $status -eq 0 ]]; then
    status=$EX_NOREPORT
  fi
  return $status
}

run_npm_tests() {
  require node
  require npm

  # Installation reproductible des dépendances (cf. README : `npm ci` en CI).
  if [[ ! -d "$PROJECT_DIR/node_modules" ]]; then
    # Cache npm par défaut (~/.npm) : c'est celui que restaure `cache: npm` de setup-node.
    log "npm : npm ci --prefer-offline"
    ( cd "$PROJECT_DIR" && npm ci --prefer-offline )
    if [[ $? -ne 0 ]]; then
      fail "$EX_DEPENDENCY" "Échec de 'npm ci'."
    fi
  fi

  # karma.conf.js configure déjà ChromeHeadless et karma-junit-reporter
  # (sortie dans reports/<navigateur>/*.xml) ; `npm test` = `ng test --watch false`.
  rm -rf "$PROJECT_DIR/reports"

  log "npm : npm test"
  ( cd "$PROJECT_DIR" && npm test )
  local status=$?

  # Les rapports sont copiés même en cas d'échec pour que la CI puisse les publier.
  if ! copy_reports "$PROJECT_DIR/reports" && [[ $status -eq 0 ]]; then
    status=$EX_NOREPORT
  fi
  return $status
}

main
