#!/usr/bin/env python3
"""
Claude Code session manager for tmux.

Scans ~/.claude/projects, previews transcripts with fzf, restores sessions into
normal tmux windows/panes, and moves deleted transcripts to a local trash.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import unicodedata
from dataclasses import dataclass
from typing import Iterable


HOME = pathlib.Path.home()
CLAUDE_DIR = pathlib.Path(os.environ.get("CLAUDE_CONFIG_DIR", HOME / ".claude")).expanduser()
PROJECTS_DIR = CLAUDE_DIR / "projects"
TRASH_DIR = pathlib.Path(
    os.environ.get(
        "CLAUDE_SESSION_TRASH_DIR",
        HOME / ".local" / "share" / "tmux-claude-sessions" / "trash",
    )
).expanduser()


@dataclass
class Session:
    file: pathlib.Path
    session_id: str
    cwd: str
    project: str
    title: str
    updated: float
    message_count: int
    size_bytes: int
    status: str


def run(args: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(args, text=True, **kwargs)


def command_exists(name: str) -> bool:
    return shutil.which(name) is not None


def human_size(size: int) -> str:
    if size >= 1024 * 1024:
        return f"{size / (1024 * 1024):.1f} MB"
    if size >= 1024:
        return f"{size / 1024:.1f} KB"
    return f"{size} B"


def fmt_time(epoch: float) -> str:
    return dt.datetime.fromtimestamp(epoch).strftime("%Y-%m-%d %H:%M")


def clean_cell(value: str, limit: int = 120) -> str:
    value = re.sub(r"\s+", " ", value).strip().replace("\t", " ")
    if len(value) > limit:
        return value[: limit - 1] + "…"
    return value


def display_width(value: str) -> int:
    width = 0
    for char in value:
        if unicodedata.combining(char):
            continue
        width += 2 if unicodedata.east_asian_width(char) in ("F", "W") else 1
    return width


def fit(value: str, width: int) -> str:
    value = clean_cell(value, width * 2)
    result = ""
    current = 0
    for char in value:
        char_width = 2 if unicodedata.east_asian_width(char) in ("F", "W") else 1
        if current + char_width > width:
            break
        result += char
        current += char_width
    if result != value and width > 1:
        while display_width(result) > width - 1:
            result = result[:-1]
        result += "…"
    return result + (" " * max(0, width - display_width(result)))


def is_noise_message(body: str) -> bool:
    body = body.strip()
    return (
        body.startswith("<local-command-caveat>")
        or body.startswith("<local-command-stdout>")
        or body.startswith("<local-command-stderr>")
        or body.startswith("<command-name>")
    )


def content_text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict):
                item_type = item.get("type")
                if item_type in (None, "text"):
                    text = item.get("text")
                    if isinstance(text, str):
                        parts.append(text)
        return "\n".join(parts)
    return ""


def message_role(record: dict) -> str:
    message = record.get("message")
    if isinstance(message, dict) and isinstance(message.get("role"), str):
        return message["role"]
    if isinstance(record.get("role"), str):
        return record["role"]
    return ""


def message_body(record: dict) -> str:
    message = record.get("message")
    if isinstance(message, dict):
        return content_text(message.get("content"))
    return content_text(record.get("content") or record.get("text"))


def parse_timestamp(value: str | None) -> float | None:
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def project_from_cwd(cwd: str, file: pathlib.Path) -> str:
    if cwd:
        name = pathlib.Path(cwd).name
        if name:
            return name
    parent = file.parent
    while parent != PROJECTS_DIR and parent.parent != parent:
        if parent.parent == PROJECTS_DIR:
            return parent.name
        parent = parent.parent
    return file.parent.name


def iter_session_files() -> Iterable[pathlib.Path]:
    if not PROJECTS_DIR.exists():
        return []
    return (
        path
        for path in PROJECTS_DIR.rglob("*.jsonl")
        if "/subagents/" not in path.as_posix()
    )


def active_session_ids() -> set[str]:
    if not command_exists("tmux"):
        return set()
    proc = run(
        ["tmux", "list-panes", "-a", "-F", "#{@claude_session_id}"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if proc.returncode != 0:
        return set()
    return {line.strip() for line in proc.stdout.splitlines() if line.strip()}


def scan_one(file: pathlib.Path, active_ids: set[str]) -> Session | None:
    stat = file.stat()
    session_id = file.stem
    cwd = ""
    title = ""
    updated = stat.st_mtime
    message_count = 0

    try:
        with file.open("r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(record.get("sessionId"), str):
                    session_id = record["sessionId"]
                if not cwd and isinstance(record.get("cwd"), str):
                    cwd = record["cwd"]
                ts = parse_timestamp(record.get("timestamp"))
                if ts is not None:
                    updated = max(updated, ts)
                role = message_role(record)
                if role in ("user", "assistant"):
                    body = clean_cell(message_body(record), 500)
                    if body and not is_noise_message(body):
                        message_count += 1
                        if not title and role == "user":
                            title = clean_cell(body, 90)
    except OSError:
        return None

    if not title:
        title = session_id
    if session_id in active_ids:
        status = "active"
    elif cwd and pathlib.Path(cwd).exists():
        status = "ready"
    else:
        status = "missing"

    return Session(
        file=file,
        session_id=session_id,
        cwd=cwd,
        project=project_from_cwd(cwd, file),
        title=title,
        updated=updated,
        message_count=message_count,
        size_bytes=stat.st_size,
        status=status,
    )


def scan_sessions() -> list[Session]:
    active_ids = active_session_ids()
    sessions = []
    for file in iter_session_files():
        session = scan_one(file, active_ids)
        if session is not None:
            sessions.append(session)
    rank = {"active": 0, "ready": 1, "missing": 2}
    sessions.sort(key=lambda s: (rank.get(s.status, 9), -s.updated, s.project.lower()))
    return sessions


def print_list() -> None:
    for session in scan_sessions():
        short_id = session.session_id[:8]
        project_path = session.cwd or str(session.file.parent)
        visible = (
            f"{short_id:<8}  "
            f"{fmt_time(session.updated):<16}  "
            f"{session.status:<7}  "
            f"{fit(project_path, 46)}  "
            f"{fit(session.title, 44)}  "
            f"{session.message_count:>4}  "
            f"{human_size(session.size_bytes):>9}"
        )
        row = [
            str(session.file),
            visible,
            session.session_id,
        ]
        print("\t".join(row))


def preview(file_value: str) -> None:
    file = pathlib.Path(file_value)
    if not file.exists():
        print("Session file not found.")
        return
    session = scan_one(file, active_session_ids())
    if session is None:
        print("Unable to read session.")
        return

    # For a live Claude session, use the exact same source as the pane
    # navigator. This preserves terminal prompts, colors, wrapping, tool
    # output, and the current scrollback instead of reconstructing it from
    # the JSONL transcript.
    if command_exists("tmux"):
        proc = run(
            [
                "tmux",
                "list-panes",
                "-a",
                "-F",
                "#{pane_id}\t#{@claude_session_id}",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        if proc.returncode == 0:
            for line in proc.stdout.splitlines():
                pane_id, _, pane_session_id = line.partition("\t")
                if pane_session_id.strip() != session.session_id:
                    continue
                try:
                    pane_height = int(
                        run(
                            ["tmux", "display-message", "-t", pane_id, "-p", "#{pane_height}"],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL,
                        ).stdout.strip()
                    )
                except (TypeError, ValueError):
                    pane_height = 0
                try:
                    preview_lines = int(os.environ.get("FZF_PREVIEW_LINES", "0"))
                except ValueError:
                    preview_lines = 0
                start = max(0, pane_height - preview_lines) if preview_lines else 0
                capture = run(
                    [
                        "tmux",
                        "capture-pane",
                        "-pe",
                        "-S",
                        str(start),
                        "-t",
                        pane_id,
                    ],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                )
                if capture.returncode == 0:
                    print(capture.stdout, end="")
                    return

    messages: list[tuple[str, str]] = []
    try:
        with file.open("r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue
                role = message_role(record)
                if role not in ("user", "assistant"):
                    continue
                body = message_body(record).rstrip()
                if not body or is_noise_message(body):
                    continue
                if len(body) > 4000:
                    body = body[:4000] + "\n…"
                messages.append((role, body))
    except OSError as exc:
        print(exc)
        return

    for role, body in messages[-18:]:
        label = "User" if role == "user" else "Claude"
        color = "\033[36m" if role == "user" else "\033[32m"
        print(f"{color}{label}\033[0m")
        print(body)
        print()


def read_session_by_file(file_value: str) -> Session:
    session = scan_one(pathlib.Path(file_value), active_session_ids())
    if session is None:
        raise RuntimeError(f"cannot read session: {file_value}")
    return session


def shell_quote(value: str) -> str:
    import shlex

    return shlex.quote(value)


def claude_command(session: Session) -> str:
    sid = shell_quote(session.session_id)
    return f"tmux set-option -p @claude_session_id {sid}; exec claude --resume {sid}"


def window_name(session: Session) -> str:
    raw = f"claude-{session.project or 'session'}"
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", raw)[:40] or "claude"


def open_session(session: Session, mode: str) -> None:
    cwd = session.cwd if session.cwd and pathlib.Path(session.cwd).exists() else str(HOME)
    cmd = claude_command(session)
    if mode == "window":
        run(["tmux", "new-window", "-c", cwd, "-n", window_name(session), cmd], check=True)
    elif mode == "split_h":
        run(["tmux", "split-window", "-h", "-c", cwd, cmd], check=True)
    elif mode == "split_v":
        run(["tmux", "split-window", "-v", "-c", cwd, cmd], check=True)
    elif mode == "current":
        origin = os.environ.get("TMUX_ORIGIN_PANE", "")
        if not origin:
            raise RuntimeError("TMUX_ORIGIN_PANE is not set")
        typed = f"cd {shell_quote(cwd)} && {cmd}"
        run(["tmux", "send-keys", "-t", origin, typed, "C-m"], check=True)
    else:
        raise RuntimeError(f"unknown open mode: {mode}")


def trash_session(session: Session) -> pathlib.Path:
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    dest_dir = TRASH_DIR / f"{stamp}-{session.session_id}"
    dest_dir.mkdir(parents=True, exist_ok=False)
    dest_file = dest_dir / session.file.name
    metadata = {
        "session_id": session.session_id,
        "source_path": str(session.file),
        "project_path": session.cwd,
        "deleted_at": dt.datetime.now().isoformat(timespec="seconds"),
    }
    (dest_dir / "metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    shutil.move(str(session.file), str(dest_file))
    return dest_dir


def delete_session_permanently(session: Session) -> None:
    session.file.unlink()


def copy_id(file_value: str) -> None:
    session = read_session_by_file(file_value)
    if command_exists("pbcopy"):
        proc = run(["pbcopy"], input=session.session_id)
        if proc.returncode == 0:
            return
    print(session.session_id)


def ensure_deps() -> None:
    missing = [name for name in ("fzf", "tmux", "claude") if not command_exists(name)]
    if missing:
        print("Missing dependencies: " + ", ".join(missing), file=sys.stderr)
        sys.exit(1)
    if not PROJECTS_DIR.exists():
        print(f"Claude projects directory not found: {PROJECTS_DIR}", file=sys.stderr)
        sys.exit(1)


def fzf_ui() -> None:
    ensure_deps()
    script = pathlib.Path(__file__).resolve()
    list_cmd = f"{shell_quote(str(script))} --list"
    preview_cmd = f"{shell_quote(str(script))} --preview {{1}}"
    copy_cmd = f"{shell_quote(str(script))} --copy-id {{1}}"

    env = os.environ.copy()
    env["FZF_DEFAULT_COMMAND"] = list_cmd
    proc = run(
        [
            "fzf",
            "--ansi",
            "--layout=reverse",
            "--info=inline",
            "--padding=1",
            "--border=rounded",
            "--border-label= Enter window  Ctrl-v right  Ctrl-s bottom  Ctrl-o origin  Ctrl-x trash  Ctrl-y copy  Ctrl-r refresh  Alt-p preview ",
            "--border-label-pos=2:bottom",
            "--input-border=rounded",
            "--input-label= Search Claude sessions ",
            "--list-border=rounded",
            "--list-label= Sessions ",
            "--preview-border=rounded",
            "--preview-label= Preview ",
            "--preview-window=down:55%",
            "--multi",
            "--gutter= ",
            "--scrollbar=│",
            "--prompt=Claude > ",
            "--pointer= ",
            "--marker=● ",
            "--color=bg:-1,bg+:#292e42,gutter:-1,fg:#a9b1d6,fg+:#c0caf5,hl:#7dcfff,hl+:#7dcfff,header:#737aa2,info:#7aa2f7,prompt:#7dcfff,pointer:#bb9af7,marker:#9ece6a,spinner:#e0af68,border:#3b4261,label:#7aa2f7,preview-bg:-1",
            "--delimiter=\t",
            "--with-nth=2",
            "--nth=2,3",
            "--header=ID        UPDATED           STATUS   PROJECT PATH                                    TITLE                                           MSG       SIZE",
            f"--preview={preview_cmd}",
            "--expect=enter,ctrl-v,ctrl-s,ctrl-o,ctrl-x",
            "--bind=ctrl-i:toggle",
            "--bind=ctrl-x:select+accept",
            "--bind=alt-p:toggle-preview",
            f"--bind=ctrl-r:reload({list_cmd})",
            f"--bind=ctrl-y:execute-silent({copy_cmd})",
        ],
        env=env,
        stdout=subprocess.PIPE,
    )
    if proc.returncode != 0 or not proc.stdout.strip():
        return

    lines = proc.stdout.splitlines()
    key = lines[0].strip()
    rows = lines[1:]
    row = rows[0] if rows else ""
    if not row:
        return
    file_value = row.split("\t", 1)[0]
    session = read_session_by_file(file_value)

    if key == "ctrl-x":
        sessions = []
        seen_files = set()
        for selected_row in rows:
            selected_file = selected_row.split("\t", 1)[0]
            if selected_file in seen_files:
                continue
            seen_files.add(selected_file)
            try:
                sessions.append(read_session_by_file(selected_file))
            except RuntimeError:
                continue
        if not sessions:
            sessions = [session]
        print()
        print(f"Delete {len(sessions)} Claude session(s):")
        for selected_session in sessions[:8]:
            print(f"- {selected_session.project}: {selected_session.title}")
        if len(sessions) > 8:
            print(f"- ... and {len(sessions) - 8} more")
        print()
        choice = input("[t]rash  [d]elete permanently  [Enter] cancel: ").strip().lower()
        if choice not in ("t", "d"):
            os.execv(sys.executable, [sys.executable, str(script)])
        print()
        confirm = input("Type y to confirm: ").strip().lower()
        if confirm == "y":
            for selected_session in sessions:
                if choice == "t":
                    trash_session(selected_session)
                else:
                    delete_session_permanently(selected_session)
            print(
                f"{'Moved to trash' if choice == 't' else 'Permanently deleted'} "
                f"{len(sessions)} session(s)."
            )
            input("Press Enter to return to sessions...")
        os.execv(sys.executable, [sys.executable, str(script)])
        return

    mode_by_key = {
        "": "window",
        "enter": "window",
        "ctrl-v": "split_h",
        "ctrl-s": "split_v",
        "ctrl-o": "current",
    }
    open_session(session, mode_by_key.get(key, "window"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--preview")
    parser.add_argument("--copy-id")
    args = parser.parse_args()

    if args.list:
        print_list()
    elif args.preview:
        preview(args.preview)
    elif args.copy_id:
        copy_id(args.copy_id)
    else:
        fzf_ui()


if __name__ == "__main__":
    main()
