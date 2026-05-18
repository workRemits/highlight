# Extended frontend entrypoint that ALSO swaps OAuth client IDs at runtime.
#
# Path B alternative to rebuilding the frontend image. Lets you ship the
# official ghcr.io/highlight/highlight-frontend image but rewrite the
# integration client IDs (Slack/Linear/etc.) on container start, so OAuth
# flows redirect to your self-hosted callback URLs and use YOUR registered
# OAuth apps.
#
# Required Coolify env vars per client ID you want to swap:
#   <NAME>_CLIENT_ID_UPSTREAM   The literal Highlight Cloud value to replace
#                               (discoverable from the running bundle -- see
#                                Path B Step 1 in the project docs)
#   <NAME>_CLIENT_ID            YOUR registered OAuth app's client ID
#
# Example:
#   SLACK_CLIENT_ID_UPSTREAM=1234567890.0987654321   # Highlight's
#   SLACK_CLIENT_ID=9876543210.1122334455            # yours
#
# If either var is unset for a given integration, that integration is skipped.

import os
import re
import subprocess

CONSTANTS_FILE = "/build/frontend/build/assets/constants.js"
NGINX_CONFIG_FILE = "/etc/nginx/conf.d/default.conf"

URL_ENVS = {
    "REACT_APP_PRIVATE_GRAPH_URI": "https://pri.highlight.io",
    "REACT_APP_PUBLIC_GRAPH_URI": "https://pub.highlight.io",
    "REACT_APP_FRONTEND_URI": "https://app.highlight.io",
    "REACT_APP_AUTH_MODE": "firebase",
    "REACT_APP_OTLP_ENDPOINT": "https://otel.highlight.io:4318",
    "REACT_APP_DISABLE_ANALYTICS": "false",
}

# Integration client IDs we know how to swap. Add to this list when wiring
# up new vendors -- the script handles any name, you just need the two env
# vars: <NAME>_UPSTREAM and <NAME>.
INTEGRATION_CLIENT_IDS = [
    "SLACK_CLIENT_ID",
    "LINEAR_CLIENT_ID",
    "GITHUB_CLIENT_ID",
    "JIRA_CLIENT_ID",
    "DISCORD_CLIENT_ID",
    "CLICKUP_CLIENT_ID",
    "GITLAB_CLIENT_ID",
    "HEIGHT_CLIENT_ID",
    "MICROSOFT_TEAMS_BOT_ID",
]

# GitHub uses a GitHub App, not OAuth. The App slug "highlight-io" is hardcoded
# in the URL path (apps/highlight-io/installations/new), so a client-ID swap
# is not enough. Set GITHUB_APP_SLUG to YOUR registered GitHub App's slug to
# rewrite the install URL too.
GITHUB_APP_SLUG_UPSTREAM = "highlight-io"

# Walk the build output to find all JS files (the bundle name has a hash
# suffix that changes on every Highlight release, so we can't hard-code it).
def find_js_files():
    base = "/build/frontend/build/assets"
    for fname in os.listdir(base):
        if fname.endswith(".js"):
            yield os.path.join(base, fname)


def swap_in_file(path, replacements):
    with open(path, "r") as f:
        data = f.read()
    changed = False
    for old, new in replacements:
        if old in data:
            data = data.replace(old, new)
            changed = True
            print(f"  swapped {old!r} -> {new!r} in {path}", flush=True)
    if changed:
        with open(path, "w") as f:
            f.write(data)


def main():
    use_ssl = os.environ.get("SSL") != "false"

    # Pass 1: URL replacements in constants.js (unchanged from upstream)
    with open(CONSTANTS_FILE, "r") as f:
        data = f.read()
        print("read constants file", data, flush=True)

    for key, default in URL_ENVS.items():
        env = os.environ.get(key)
        if env:
            print("replacing", {key: key, "default": default, "value": env}, flush=True)
            data = re.sub(default, env, data)
    try:
        with open(CONSTANTS_FILE, "w") as f:
            f.write(data)
            print("wrote back constants file", data, flush=True)
    except Exception as e:
        print("failed to write back constants file", e, data, flush=True)

    # Pass 2: client-ID literal swaps across all JS assets
    replacements = []
    for var in INTEGRATION_CLIENT_IDS:
        upstream = os.environ.get(var + "_UPSTREAM")
        ours = os.environ.get(var)
        if not upstream or not ours:
            print(f"skipping {var}: needs both {var}_UPSTREAM and {var}", flush=True)
            continue
        if upstream == ours:
            print(f"skipping {var}: upstream == ours, no swap needed", flush=True)
            continue
        replacements.append((upstream, ours))
        print(f"queued swap for {var}", flush=True)

    # GitHub App slug swap (URL path, not query param)
    github_slug = os.environ.get("GITHUB_APP_SLUG")
    if github_slug and github_slug != GITHUB_APP_SLUG_UPSTREAM:
        old_path = f"apps/{GITHUB_APP_SLUG_UPSTREAM}/installations"
        new_path = f"apps/{github_slug}/installations"
        replacements.append((old_path, new_path))
        print(f"queued GitHub App slug swap: {GITHUB_APP_SLUG_UPSTREAM} -> {github_slug}", flush=True)

    if replacements:
        print(f"swapping {len(replacements)} literals across JS bundles", flush=True)
        for js_path in find_js_files():
            swap_in_file(js_path, replacements)
    else:
        print("no integration swaps configured", flush=True)

    # Pass 3: nginx SSL toggle (unchanged from upstream)
    with open(NGINX_CONFIG_FILE, "r") as f:
        nginx_data = f.read()
        if not use_ssl:
            nginx_data = re.sub("ssl http2 ", "", nginx_data, flags=re.MULTILINE)
    try:
        with open(NGINX_CONFIG_FILE, "w") as f:
            f.write(nginx_data)
            print("wrote back nginx file", nginx_data, flush=True)
    except Exception as e:
        print("failed to write back nginx file", e, nginx_data, flush=True)

    return subprocess.check_call(["nginx", "-g", "daemon off;"])


if __name__ == "__main__":
    main()
