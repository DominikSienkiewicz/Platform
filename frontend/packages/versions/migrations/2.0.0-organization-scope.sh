# shellcheck shell=bash
# Platform należy od 2026-11-13 do organizacji SeniorDeveloper-pl-Dominik-Sienkiewicz, a GitHub Packages npm wymaga
# scope równego ownerowi repo: paczki @dominiksienkiewicz/* zostają na koncie osobistym, nowe wydania są pod
# @seniordeveloper-pl-dominik-sienkiewicz/*. Przepisuje scope, referencje workflowów Platform, URL GitHub Packages
# w settings i stub; inne wzmianki o koncie osobistym (repo, obrazy GHCR, dokumentacja) zostawia jako notatki.
describe() { echo "move the npm scope, the Platform references and the stub to the organization SeniorDeveloper-pl-Dominik-Sienkiewicz"; }
touches() { python3 "$MIGRATION_LIB/organization.py" files; }
detect() { python3 "$MIGRATION_LIB/organization.py" detect; }
apply() { python3 "$MIGRATION_LIB/organization.py" apply; }
