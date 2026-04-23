"""
AI code review via OpenRouter (Claude).

Reads pr_diff.txt (full PR diff, all file types), sends it to the model,
and posts (or replaces) a review comment on the PR. Requires environment
variables: OPENROUTER_API_KEY, GH_TOKEN, PR_NUMBER, REPO
"""
import json
import os
import subprocess
import urllib.request

DIFF_FILE = "pr_diff.txt"
CLAUDE_MD = "CLAUDE.md"
MAX_DIFF_CHARS = 60_000
MODEL = "anthropic/claude-opus-4"

SYSTEM_PROMPT = """\
Senior engineer. Review diff for all changed files — Swift, CI workflows, \
build config, scripts, tests, docs, and any other codebase changes.

Flag: correctness bugs, logic errors, memory/retain issues, silent failure paths, \
DRY violations, dead/unused code, long-term maintainability risks, readability problems, \
CI misconfigurations, missing test coverage for behavioral changes.
Skip: style, formatting, brace placement — linters own that.

Format: GitHub-flavored markdown."""


def load_claude_md() -> str:
    """Load CLAUDE.md for project conventions and communication style."""
    if os.path.exists(CLAUDE_MD):
        with open(CLAUDE_MD) as f:
            return f.read()
    return ""


def call_openrouter(api_key: str, repo: str, diff: str) -> str:
    claude_md = load_claude_md()
    system = SYSTEM_PROMPT
    if claude_md:
        system += f"\n\nProject conventions and style (from CLAUDE.md):\n\n{claude_md}"

    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system},
            {
                "role": "user",
                "content": f"Review this diff:\n\n```diff\n{diff}\n```",
            },
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


def delete_previous_review(repo: str, pr_number: str) -> None:
    """Remove any existing AI review comment so we don't stack duplicates."""
    result = subprocess.run(
        [
            "gh", "api", f"repos/{repo}/issues/{pr_number}/comments",
            "--jq", '.[] | select(.body | startswith("<!-- ai-review -->")) | .id',
        ],
        capture_output=True,
        text=True,
    )
    for comment_id in result.stdout.strip().splitlines():
        subprocess.run(
            ["gh", "api", "-X", "DELETE", f"repos/{repo}/issues/comments/{comment_id}"],
            check=True,
        )


def main() -> None:
    api_key = os.environ["OPENROUTER_API_KEY"]
    pr_number = os.environ["PR_NUMBER"]
    repo = os.environ["REPO"]

    with open(DIFF_FILE) as f:
        diff = f.read()

    if len(diff) > MAX_DIFF_CHARS:
        diff = diff[:MAX_DIFF_CHARS] + "\n\n[diff truncated — showing first 60,000 characters]"

    print(f"Sending {len(diff):,} chars to {MODEL}...")
    review = call_openrouter(api_key, repo, diff)

    delete_previous_review(repo, pr_number)

    comment_body = f"<!-- ai-review -->\n### AI Code Review\n\n{review}"
    subprocess.run(
        ["gh", "pr", "comment", pr_number, "--repo", repo, "--body", comment_body],
        check=True,
    )
    print("Review posted.")


if __name__ == "__main__":
    main()
