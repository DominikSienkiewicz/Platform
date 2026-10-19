"""Jeden silnik porównania kanonu Platform (N-REL-8), na sparsowanych wartościach, nie na tekście.

Woła go scripts/canon-diff.py (PR do Platform, dwie rewizje gita) i bump-report.py (konsument, dwa wydania).
Porównuje katalog (libs.versions.toml), kanon frontendu (versions.json) i kontrakt callerów reusable workflowów
(workflow-contract.txt). Akcja konsumenta (ADR-0002, MINOR w linii 1.x): usunięty alias katalogu, paczka
usunięta z kanonu, a w kontrakcie usunięte wejście albo sekret, nowe wymagane wejście, nowe lub wyższe uprawnienie
i zmieniona wartość domyślna. Zmiana wersji nią nie jest — platform-bump ją przenosi i regeneruje lockfile'y.
"""

import json
import os
import re

SECTIONS = ("versions", "libraries", "bundles", "plugins")
ACCESSOR = {"versions": "libs.versions.", "libraries": "libs.", "bundles": "libs.bundles.", "plugins": "libs.plugins."}
LEVEL = {"none": 0, "read": 1, "write": 2}
LEVEL_NAME = {level: name for name, level in LEVEL.items()}


class Change:
    """Jedna zmiana: `line` do raportu, `action`, gdy wymaga ruchu konsumenta, i to, czego dotyczy."""

    def __init__(self, kind, key, line, action=None, aliases=()):
        self.kind = kind
        self.key = key
        self.line = line
        self.action = action
        self.aliases = tuple(aliases)


# --- TOML: tomllib od Pythona 3.11; macOS ma systemowy 3.9, więc katalog czyta też mały parser niżej ---------


def parse_toml(text):
    if not os.environ.get("PLATFORM_TOML_FALLBACK"):
        try:
            import tomllib

            return tomllib.loads(text)
        except ModuleNotFoundError:
            pass
    return _MiniToml(text).parse()


class _MiniToml:
    """Podzbiór TOML katalogu wersji Gradle: tabele [x], klucze z kropkami, stringi, tablice i tabele inline."""

    def __init__(self, text):
        self.text = text
        self.at = 0

    def parse(self):
        root = {}
        table = root
        while True:
            self._skip(newlines=True)
            if self.at >= len(self.text):
                return root
            if self.text[self.at] == "[":
                end = self.text.index("]", self.at)
                table = root
                for part in self.text[self.at + 1 : end].strip().split("."):
                    table = table.setdefault(part.strip(), {})
                self.at = end + 1
                continue
            keys = self._key()
            self._skip()
            self._expect("=")
            self._assign(table, keys, self._value())

    def _assign(self, table, keys, value):
        for key in keys[:-1]:
            table = table.setdefault(key, {})
        table[keys[-1]] = value

    def _skip(self, newlines=False):
        while self.at < len(self.text):
            char = self.text[self.at]
            if char == "#":
                while self.at < len(self.text) and self.text[self.at] != "\n":
                    self.at += 1
            elif char in " \t\r" or (newlines and char == "\n"):
                self.at += 1
            else:
                return

    def _expect(self, char):
        if self.text[self.at] != char:
            raise ValueError(f"TOML: expected {char!r} at {self.at}")
        self.at += 1

    def _key(self):
        keys = []
        while True:
            self._skip()
            if self.text[self.at] == '"':
                keys.append(self._string())
            else:
                match = re.compile(r"[A-Za-z0-9_-]+").match(self.text, self.at)
                if not match:
                    raise ValueError(f"TOML: expected a key at {self.at}")
                keys.append(match.group(0))
                self.at = match.end()
            self._skip()
            if self.at < len(self.text) and self.text[self.at] == ".":
                self.at += 1
                continue
            return keys

    def _string(self):
        self._expect('"')
        out = []
        while self.text[self.at] != '"':
            char = self.text[self.at]
            if char == "\\":
                self.at += 1
                char = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(self.text[self.at], self.text[self.at])
            out.append(char)
            self.at += 1
        self.at += 1
        return "".join(out)

    def _value(self):
        self._skip()
        char = self.text[self.at]
        if char == '"':
            return self._string()
        if char == "[":
            self.at += 1
            items = []
            while True:
                self._skip(newlines=True)
                if self.text[self.at] == "]":
                    self.at += 1
                    return items
                items.append(self._value())
                self._skip(newlines=True)
                if self.text[self.at] == ",":
                    self.at += 1
        if char == "{":
            self.at += 1
            table = {}
            while True:
                self._skip()
                if self.text[self.at] == "}":
                    self.at += 1
                    return table
                keys = self._key()
                self._expect("=")
                self._assign(table, keys, self._value())
                self._skip()
                if self.text[self.at] == ",":
                    self.at += 1
        match = re.compile(r"true|false|[+-]?[0-9][0-9_.]*").match(self.text, self.at)
        if not match:
            raise ValueError(f"TOML: unsupported value at {self.at}")
        self.at = match.end()
        word = match.group(0)
        return {"true": True, "false": False}.get(word, word)


# --- Wczytanie trzech źródeł ---------------------------------------------------------------------------------


def catalog_from_text(text):
    parsed = parse_toml(text) if text else {}
    return {section: parsed.get(section, {}) for section in SECTIONS}


def canon_from_text(text):
    return json.loads(text).get("versions", {}) if text else {}


def contract_from_text(text):
    """{workflow: {"input": {name: (required, default)}, "secret": {name: required}, "permission": {scope: level}}}"""
    workflows = {}
    for line in (text or "").splitlines():
        parts = line.split(" ")
        if len(parts) < 3:
            continue
        workflow = workflows.setdefault(parts[0], {"input": {}, "secret": {}, "permission": {}})
        if parts[1] == "input":
            attributes = dict(part.split("=", 1) for part in parts[3:] if "=" in part)
            workflow["input"][parts[2]] = (attributes.get("required") == "true", attributes.get("default"))
        elif parts[1] == "secret":
            workflow["secret"][parts[2]] = "required=true" in parts[3:]
        elif parts[1] in ("permissions", "job"):
            rest = " ".join(parts[2:] if parts[1] == "permissions" else parts[4:])
            if ":" in rest:
                scope, level = (part.strip() for part in rest.split(":", 1))
                workflow["permission"][scope] = max(workflow["permission"].get(scope, 0), LEVEL.get(level, 0))
    return workflows


def describe(value):
    if isinstance(value, dict):
        version = value.get("version")
        if isinstance(version, dict) and "ref" in version:
            return f"version.ref {version['ref']}"
        if version is not None:
            return str(version)
        return ", ".join(f"{key}={describe(item)}" for key, item in sorted(value.items()))
    return str(value)


def alias(section, key):
    return ACCESSOR[section] + key.replace("-", ".").replace("_", ".")


def _version_users(catalog, version_key):
    """Aliasy bibliotek i pluginów, które biorą wersję przez version.ref."""
    users = []
    for section in ("libraries", "plugins"):
        for key, value in catalog[section].items():
            if isinstance(value, dict) and isinstance(value.get("version"), dict) and value["version"].get("ref") == version_key:
                users.append(alias(section, key))
    return users


# --- Zmiany --------------------------------------------------------------------------------------------------


def catalog_changes(old, new):
    changes = []
    for section in SECTIONS:
        for key in sorted(set(old[section]) | set(new[section])):
            before, after = old[section].get(key), new[section].get(key)
            name = alias(section, key)
            users = [name] + (_version_users(new if after is not None else old, key) if section == "versions" else [])
            if before is None:
                changes.append(Change("catalog", key, f"catalog `{name}` added: {describe(after)}", aliases=users))
            elif after is None:
                changes.append(
                    Change("catalog", key, f"catalog `{name}` removed", f"a build that uses `{name}` no longer resolves it", users)
                )
            elif before != after:
                changes.append(Change("catalog", key, f"catalog `{name}`: {describe(before)} → {describe(after)}", aliases=users))
    return changes


def canon_changes(old, new):
    changes = []
    for name in sorted(set(old) | set(new)):
        before, after = old.get(name), new.get(name)
        if before is None:
            changes.append(Change("canon", name, f"frontend canon `{name}` added: {after}"))
        elif after is None:
            changes.append(
                Change("canon", name, f"frontend canon `{name}` removed", f"`platform-versions-check` fails a frontend that still depends on `{name}`")
            )
        elif before != after:
            changes.append(Change("canon", name, f"frontend canon `{name}`: {before} → {after}"))
    return changes


def contract_changes(old, new):
    changes = []
    empty = {"input": {}, "secret": {}, "permission": {}}
    for workflow in sorted(set(old) | set(new)):
        before = old.get(workflow, empty)
        after = new.get(workflow)
        add = lambda line, action=None: changes.append(Change("workflow", workflow, line, action))
        if after is None:
            add(f"`{workflow}` removed", f"a caller of `{workflow}` fails")
            continue
        if workflow not in old:
            add(f"`{workflow}` added")
            continue
        for name in sorted(set(before["input"]) | set(after["input"])):
            was, now = before["input"].get(name), after["input"].get(name)
            if was is None:
                add(
                    f"`{workflow}` input `{name}` added" + (" (required)" if now[0] else ""),
                    f"every caller of `{workflow}` must pass the new required input `{name}`" if now[0] else None,
                )
            elif now is None:
                add(f"`{workflow}` input `{name}` removed", f"a caller of `{workflow}` that passes `{name}` fails")
            elif was != now:
                add(
                    f"`{workflow}` input `{name}`: required={was[0]} default={was[1]} → required={now[0]} default={now[1]}",
                    f"`{workflow}` input `{name}` changed its default or became required",
                )
        for name in sorted(set(before["secret"]) - set(after["secret"])):
            add(f"`{workflow}` secret `{name}` removed", f"a caller of `{workflow}` that passes the secret `{name}` fails")
        for name in sorted(set(after["secret"]) - set(before["secret"])):
            add(f"`{workflow}` secret `{name}` added")
        for scope in sorted(set(before["permission"]) | set(after["permission"])):
            was, now = before["permission"].get(scope, 0), after["permission"].get(scope, 0)
            if now > was:
                add(
                    f"`{workflow}` needs `{scope}: {LEVEL_NAME[now]}` (was {LEVEL_NAME[was]})",
                    f"every caller of `{workflow}` must grant `{scope}: {LEVEL_NAME[now]}`",
                )
            elif now < was:
                add(f"`{workflow}` no longer needs `{scope}` at its former level")
    return changes
