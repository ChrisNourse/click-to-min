"""
AI code review via OpenRouter (Claude).

Posts pull request reviews with per-file inline comments (each individually
resolvable). On subsequent pushes, reviews only the incremental diff and
checks whether previous suggestions were resolved.

Requires env: OPENROUTER_API_KEY, GH_TOKEN, PR_NUMBER, REPO, EVENT_ACTION
"""
import json
import os
import subprocess
import urllib.request

FULL_DIFF = "pr_diff.txt"
INCREMENTAL_DIFF = "pr_incremental_diff.txt"
CLAUDE_MD = "CLAUDE.md"
MAX_DIFF_CHARS = 60_000
MODEL = "anthropic/claude-opus-4"
AI_REVIEW_MARKER = "<!-- ai-review-v2 -->"

SYSTEM_PROMPT = """\
Senior engineer. Review diff for all changed files — Swift, CI workflows, \
build config, scripts, tests, docs, and any other codebase changes.

Flag: correctness bugs, logic errors, memory/retain issues, silent failure paths, \
DRY violations, dead/unused code, long-term maintainability risks, readability problems, \
CI misconfigurations, missing test coverage for behavioral changes.
Skip: style, formatting, brace placement — linters own that.

Quality rules — CRITICAL:
- Only flag issues you are CERTAIN about. When in doubt, do not comment.
- NEVER suggest code that is identical to what already exists. Before writing \
a suggestion, re-read the diff line and verify your replacement actually changes something.
- Before flagging "dead code", "missing error handling", or "unnecessary fallback", \
consider whether it is intentional defensive programming.
- Understand language semantics before flagging ordering issues. Python `and` \
short-circuits left-to-right; `os.path.exists()` before `os.path.getsize()` is correct.
- Fewer high-confidence comments are better than many speculative ones.
- Do NOT invent problems. If the code is correct, return LGTM.

Return a JSON object with three fields:
- "summary": one-sentence overall assessment
- "comments": array of objects for NEW inline comments, each with:
  - "path": file path exactly as shown in diff header (after "b/")
  - "line": line number in NEW file (right side of diff, from + in @@ headers)
  - "body": one-line description: severity, problem, fix
  - "suggestion": (optional) exact replacement code for that line — only when you \
have a concrete fix that DIFFERS from the existing code
- "thread_replies": array of objects responding to replies on your previous comments, each with:
  - "thread_id": the thread_id from the previous review context
  - "body": your response — acknowledge if resolved, counter-argue if not, or concede if \
the author's argument is valid. Keep it brief.

Line number rules (for "comments" only):
- Use line numbers from the new file (number after + in @@ hunk headers)
- Only comment on lines present in the diff as additions (+) or context lines
- Never comment on deleted lines (-)

If no issues found, return {"summary": "LGTM", "comments": [], "thread_replies": []}.

Return ONLY valid JSON. No markdown fences. No text outside the JSON."""

FOLLOWUP_ADDENDUM = """\

This is a FOLLOW-UP review of incremental changes only. You are reviewing \
ONLY the new commits, not the entire PR. Focus on:
1. Respond to replies on your previous suggestions via "thread_replies" — \
thumbs up if resolved, counter-argue if not, concede if author is right
2. Any NEW issues introduced by these specific changes (via "comments")
Do NOT raise issues about code that was not changed in this diff."""


def load_claude_md() -> str:
    if os.path.exists(CLAUDE_MD):
        with open(CLAUDE_MD) as f:
            return f.read()
    return ""


def call_openrouter(api_key: str, repo: str, user_content: str, system: str) -> str:
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user_content},
        ],
    }
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "HTTP-Referer": f"https://github.com/{repo}",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        result = json.loads(resp.read())
    return result["choices"][0]["message"]["content"]


def parse_diff(diff: str) -> tuple[dict[str, set[int]], dict[tuple[str, int], str]]:
    """Parse diff into valid lines and line contents.

    Returns (valid_lines, line_contents) where:
      valid_lines: {file_path: {line_numbers}} for new-file side
      line_contents: {(file_path, line_number): content} stripped of diff prefix
    """
    valid: dict[str, set[int]] = {}
    contents: dict[tuple[str, int], str] = {}
    current_file = None
    current_line = 0
    for raw in diff.splitlines():
        if raw.startswith("diff --git"):
            current_file = None
        elif raw.startswith("+++ b/"):
            current_file = raw[6:]
            valid.setdefault(current_file, set())
        elif raw.startswith("@@ "):
            hunk_info = raw.split("+")[1].split(" ")[0]
            current_line = int(hunk_info.split(",")[0])
        elif current_file is not None and not raw.startswith("---") and not raw.startswith("\\"):
            if raw.startswith("-"):
                pass
            else:
                valid[current_file].add(current_line)
                # Store line content without the leading space/+ prefix
                contents[(current_file, current_line)] = raw[1:] if raw[:1] in ("+", " ") else raw
                current_line += 1
    return valid, contents


def get_previous_review_threads(repo: str, pr_number: str) -> list[dict]:
    """Fetch AI review threads and resolution status via GraphQL."""
    owner, name = repo.split("/")
    query = """
    query($owner: String!, $name: String!, $pr: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100) {
            nodes {
              id
              isResolved
              comments(first: 10) {
                nodes {
                  databaseId
                  body
                  path
                  line
                  author { login }
                }
              }
            }
          }
        }
      }
    }
    """
    result = subprocess.run(
        [
            "gh", "api", "graphql",
            "-f", f"query={query}",
            "-f", f"owner={owner}",
            "-f", f"name={name}",
            "-F", f"pr={pr_number}",
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Warning: could not fetch review threads: {result.stderr}")
        return []

    data = json.loads(result.stdout)
    pr_data = data.get("data", {}).get("repository", {}).get("pullRequest")
    if not pr_data:
        return []

    threads = []
    for node in pr_data["reviewThreads"]["nodes"]:
        comments = node["comments"]["nodes"]
        if not comments:
            continue
        first = comments[0]
        author = first.get("author", {}).get("login", "")
        if author not in ("github-actions[bot]", "github-actions"):
            continue
        threads.append({
            "thread_id": node["id"],
            "first_comment_db_id": first.get("databaseId"),
            "isResolved": node["isResolved"],
            "path": first.get("path"),
            "line": first.get("line"),
            "body": first.get("body", ""),
            "replies": [
                {"author": c.get("author", {}).get("login", ""), "body": c.get("body", "")}
                for c in comments[1:]
            ],
        })
    return threads


def delete_previous_issue_comments(repo: str, pr_number: str) -> None:
    """Remove old-style (v1) AI review issue comments."""
    result = subprocess.run(
        [
            "gh", "api", f"repos/{repo}/issues/{pr_number}/comments",
            "--jq", '.[] | select(.body | startswith("<!-- ai-review")) | .id',
        ],
        capture_output=True,
        text=True,
    )
    for comment_id in result.stdout.strip().splitlines():
        subprocess.run(
            ["gh", "api", "-X", "DELETE", f"repos/{repo}/issues/comments/{comment_id}"],
            capture_output=True,
        )


def post_thread_replies(repo: str, pr_number: str,
                        thread_replies: list[dict], threads: list[dict]) -> None:
    """Reply to existing review threads using the REST API."""
    thread_map = {t["thread_id"]: t for t in threads}
    posted = 0
    for reply in thread_replies:
        thread_id = reply.get("thread_id", "")
        body = reply.get("body", "")
        if not thread_id or not body or thread_id not in thread_map:
            continue
        thread = thread_map[thread_id]
        comment_id = thread.get("first_comment_db_id")
        if not comment_id:
            continue
        result = subprocess.run(
            [
                "gh", "api", "-X", "POST",
                f"repos/{repo}/pulls/{pr_number}/comments/{comment_id}/replies",
                "-f", f"body={body}",
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            posted += 1
        else:
            print(f"  reply failed for thread {thread_id}: {result.stderr}")
    if posted:
        print(f"Posted {posted} thread reply/replies.")


def create_review(repo: str, pr_number: str, summary: str,
                  comments: list[dict], valid_lines: dict[str, set[int]],
                  line_contents: dict[tuple[str, int], str]) -> None:
    """Create PR review with inline comments via GitHub API."""
    review_comments = []
    skipped = 0
    for comment in comments:
        path = comment.get("path", "")
        line = comment.get("line")
        body = comment.get("body", "")
        suggestion = comment.get("suggestion")

        if not path or not line:
            skipped += 1
            continue
        if path not in valid_lines or line not in valid_lines.get(path, set()):
            print(f"  skip: {path}:{line} not in diff")
            skipped += 1
            continue

        # Drop suggestions that are identical to existing code
        if suggestion:
            existing = line_contents.get((path, line), "")
            if suggestion.strip() == existing.strip():
                print(f"  skip: {path}:{line} suggestion identical to existing code")
                skipped += 1
                continue
            body += f"\n\n```suggestion\n{suggestion}\n```"

        review_comments.append({
            "path": path,
            "line": line,
            "side": "RIGHT",
            "body": body,
        })

    if skipped:
        print(f"Skipped {skipped} comment(s) (line not in diff).")

    review_body = f"{AI_REVIEW_MARKER}\n### AI Code Review\n\n{summary}"

    if not review_comments:
        subprocess.run(
            ["gh", "pr", "comment", pr_number, "--repo", repo, "--body", review_body],
            check=True,
        )
        print("No inline comments. Posted summary as PR comment.")
        return

    payload = {
        "body": review_body,
        "event": "COMMENT",
        "comments": review_comments,
    }
    result = subprocess.run(
        [
            "gh", "api", "-X", "POST",
            f"repos/{repo}/pulls/{pr_number}/reviews",
            "--input", "-",
        ],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Review API error: {result.stderr}")
        fallback = review_body + "\n\n" + "\n".join(
            f"- **{c['path']}:{c['line']}** — {c['body']}" for c in comments
        )
        subprocess.run(
            ["gh", "pr", "comment", pr_number, "--repo", repo, "--body", fallback],
            check=True,
        )
        print("Fell back to issue comment.")
    else:
        print(f"Review posted with {len(review_comments)} inline comment(s).")


def main() -> None:
    api_key = os.environ["OPENROUTER_API_KEY"]
    pr_number = os.environ["PR_NUMBER"]
    repo = os.environ["REPO"]
    event_action = os.environ.get("EVENT_ACTION", "opened")

    # Incremental diff for follow-up pushes, full diff for initial review
    is_followup = (
        event_action == "synchronize"
        and os.path.exists(INCREMENTAL_DIFF)
        and os.path.getsize(INCREMENTAL_DIFF) > 0
    )
    diff_file = INCREMENTAL_DIFF if is_followup else FULL_DIFF

    with open(diff_file) as f:
        diff = f.read()

    if not diff.strip():
        print("No reviewable changes.")
        return

    if len(diff) > MAX_DIFF_CHARS:
        diff = diff[:MAX_DIFF_CHARS] + "\n\n[diff truncated]"

    # Build system prompt
    claude_md = load_claude_md()
    system = SYSTEM_PROMPT
    if is_followup:
        system += FOLLOWUP_ADDENDUM
    if claude_md:
        system += f"\n\nProject conventions (from CLAUDE.md):\n\n{claude_md}"

    # Build user prompt
    label = "incremental " if is_followup else ""
    user_content = f"Review this {label}diff:\n\n```diff\n{diff}\n```"

    # Add previous review context for follow-ups
    previous = []
    if is_followup:
        previous = get_previous_review_threads(repo, pr_number)
        threads_with_replies = [t for t in previous if t["replies"]]
        threads_without_replies = [t for t in previous if not t["replies"]]
        unresolved = [t for t in previous if not t["isResolved"]]

        if previous:
            user_content += "\n\n--- Previous review context ---\n"

            if threads_with_replies:
                user_content += (
                    f"\n{len(threads_with_replies)} thread(s) have replies. "
                    "Review each reply and respond via thread_replies:\n"
                )
                for thread in threads_with_replies:
                    status = "RESOLVED" if thread["isResolved"] else "UNRESOLVED"
                    user_content += f"\n[thread_id: {thread['thread_id']}] ({status})\n"
                    user_content += f"  Your comment on {thread['path']}:{thread['line']}: {thread['body']}\n"
                    for reply in thread["replies"]:
                        user_content += f"  {reply['author']} replied: {reply['body']}\n"

            resolved_no_reply = [t for t in threads_without_replies if t["isResolved"]]
            unresolved_no_reply = [t for t in threads_without_replies if not t["isResolved"]]

            if resolved_no_reply:
                user_content += f"\n{len(resolved_no_reply)} suggestion(s) resolved without reply (no action needed).\n"
            if unresolved_no_reply:
                user_content += f"\n{len(unresolved_no_reply)} suggestion(s) still unresolved, no reply yet:\n"
                for thread in unresolved_no_reply:
                    user_content += f"- {thread['path']}:{thread['line']} — {thread['body']}\n"

            user_content += (
                "\nFor threads with replies: respond via thread_replies. "
                "Thumbs up if fixed/agreed, counter-argue if still wrong, "
                "concede if the author makes a valid point.\n"
                "For unresolved items without replies: if new diff fixes them, skip. "
                "If still broken, re-flag in comments.\n"
            )

    print(f"Sending {len(diff):,} chars to {MODEL} ({'follow-up' if is_followup else 'initial'})...")
    raw = call_openrouter(api_key, repo, user_content, system)

    # Parse JSON — strip markdown fences if Claude wrapped them
    text = raw.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1]
        if text.endswith("```"):
            text = text[:-3]
        text = text.strip()

    try:
        review = json.loads(text)
    except json.JSONDecodeError:
        print(f"JSON parse failed. Raw:\n{raw[:500]}")
        body = f"{AI_REVIEW_MARKER}\n### AI Code Review\n\n{raw}"
        subprocess.run(
            ["gh", "pr", "comment", pr_number, "--repo", repo, "--body", body],
            check=True,
        )
        return

    summary = review.get("summary", "No summary.")
    comments = review.get("comments", [])
    thread_replies = review.get("thread_replies", [])

    # Clean up old v1 issue comments
    delete_previous_issue_comments(repo, pr_number)

    # Validate comment lines against diff and filter duplicate suggestions
    valid_lines, line_contents = parse_diff(diff)
    create_review(repo, pr_number, summary, comments, valid_lines, line_contents)

    # Post replies to existing threads
    if thread_replies and previous:
        post_thread_replies(repo, pr_number, thread_replies, previous)


if __name__ == "__main__":
    main()
