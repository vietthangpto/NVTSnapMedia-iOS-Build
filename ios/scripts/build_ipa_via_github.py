#!/usr/bin/env python3
"""
NVTSnapMedia — Trình đóng gói tự động tệp cài đặt iOS (NVTSnapMedia.ipa) ngay trên Windows.
Hỗ trợ:
  - Hộp thoại giao diện Windows (Tkinter) cho phép Ctrl+V dán Token dễ dàng
  - Hoặc truyền qua tham số `--token <TOKEN>` / biến môi trường `GITHUB_TOKEN`
  - Tự động ghi nhật ký ra `build-ios-ipa.log` để dễ kiểm tra.
"""

import argparse
import base64
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

WORKSPACE_ROOT = Path(__file__).resolve().parents[2]
IOS_DIR = WORKSPACE_ROOT / "ios"
WORKFLOW_FILE = WORKSPACE_ROOT / ".github" / "workflows" / "ios-build.yml"
OUTPUT_IPA = WORKSPACE_ROOT / "NVTSnapMedia.ipa"
LOG_FILE = WORKSPACE_ROOT / "build-ios-ipa.log"
DEFAULT_REPO_NAME = "NVTSnapMedia-iOS-Build"

API_BASE = "https://api.github.com"


def log(msg: str) -> None:
    print(msg, flush=True)
    try:
        with LOG_FILE.open("a", encoding="utf-8") as f:
            f.write(msg + "\n")
    except OSError:
        pass


def gh_request(
    method: str,
    path_or_url: str,
    token: str,
    payload: dict | None = None,
    accept: str = "application/vnd.github+json",
) -> tuple[int, dict | bytes, dict]:
    url = path_or_url if path_or_url.startswith("http") else f"{API_BASE}{path_or_url}"
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", accept)
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "NVTSnapMedia-IPA-Builder/1.1")
    if data is not None:
        req.add_header("Content-Type", "application/json; charset=utf-8")

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            headers = dict(resp.headers.items())
            if accept == "application/vnd.github+json" and raw:
                return resp.status, json.loads(raw.decode("utf-8")), headers
            return resp.status, raw, headers
    except urllib.error.HTTPError as err:
        err_body = err.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"GitHub API HTTP {err.code} ({method} {path_or_url}): {err_body}") from err


def download_binary_Following_noauth_redirect(archive_url: str, token: str) -> bytes:
    class NoAuthRedirectHandler(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            new_req = urllib.request.Request(newurl, method="GET")
            new_req.add_header("User-Agent", "NVTSnapMedia-IPA-Builder/1.1")
            return new_req

    opener = urllib.request.build_opener(NoAuthRedirectHandler())
    req = urllib.request.Request(archive_url, method="GET")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    req.add_header("User-Agent", "NVTSnapMedia-IPA-Builder/1.1")
    with opener.open(req, timeout=180) as resp:
        return resp.read()


def collect_project_files() -> list[Path]:
    files: list[Path] = []
    if WORKFLOW_FILE.exists():
        files.append(WORKFLOW_FILE)
    for p in sorted(IOS_DIR.rglob("*")):
        if p.is_file() and "build" not in p.parts and "__pycache__" not in p.parts:
            files.append(p)
    return files


def ensure_repo(owner: str, repo_name: str, token: str) -> str:
    try:
        _, repo_info, _ = gh_request("GET", f"/repos/{owner}/{repo_name}", token)
        assert isinstance(repo_info, dict)
        return repo_info.get("default_branch", "main")
    except RuntimeError as exc:
        if "HTTP 404" not in str(exc):
            raise
        log(f"[*] Đang tạo kho biên dịch '{owner}/{repo_name}' trên GitHub...")
        _, created, _ = gh_request(
            "POST",
            "/user/repos",
            token,
            payload={
                "name": repo_name,
                "description": "Cloud macOS Xcode IPA Builder for NVTSnapMedia iOS",
                "private": False,
                "auto_init": True,
            },
        )
        assert isinstance(created, dict)
        time.sleep(3.0)
        return created.get("default_branch", "main")


def push_tree_commit(owner: str, repo_name: str, branch: str, token: str, files: list[Path]) -> str:
    _, ref_info, _ = gh_request("GET", f"/repos/{owner}/{repo_name}/git/ref/heads/{branch}", token)
    assert isinstance(ref_info, dict)
    base_commit_sha = ref_info["object"]["sha"]

    _, commit_info, _ = gh_request("GET", f"/repos/{owner}/{repo_name}/git/commits/{base_commit_sha}", token)
    assert isinstance(commit_info, dict)
    base_tree_sha = commit_info["tree"]["sha"]

    tree_entries = []
    log(f"[*] Đang tải lên {len(files)} tệp mã nguồn Native iOS...")
    for fpath in files:
        rel_posix = fpath.relative_to(WORKSPACE_ROOT).as_posix()
        raw = fpath.read_bytes()
        _, blob_resp, _ = gh_request(
            "POST",
            f"/repos/{owner}/{repo_name}/git/blobs",
            token,
            payload={
                "content": base64.b64encode(raw).decode("ascii"),
                "encoding": "base64",
            },
        )
        assert isinstance(blob_resp, dict)
        tree_entries.append({
            "path": rel_posix,
            "mode": "100644",
            "type": "blob",
            "sha": blob_resp["sha"],
        })

    _, new_tree, _ = gh_request(
        "POST",
        f"/repos/{owner}/{repo_name}/git/trees",
        token,
        payload={
            "base_tree": base_tree_sha,
            "tree": tree_entries,
        },
    )
    assert isinstance(new_tree, dict)

    _, new_commit, _ = gh_request(
        "POST",
        f"/repos/{owner}/{repo_name}/git/commits",
        token,
        payload={
            "message": f"Build NVTSnapMedia iOS Release .ipa ({int(time.time())})",
            "tree": new_tree["sha"],
            "parents": [base_commit_sha],
        },
    )
    assert isinstance(new_commit, dict)
    commit_sha = new_commit["sha"]

    gh_request(
        "PATCH",
        f"/repos/{owner}/{repo_name}/git/refs/heads/{branch}",
        token,
        payload={"sha": commit_sha, "force": False},
    )
    return commit_sha


def dump_failed_job_logs(owner: str, repo_name: str, run_id: int, token: str) -> None:
    try:
        _, jobs_data, _ = gh_request("GET", f"/repos/{owner}/{repo_name}/actions/runs/{run_id}/jobs", token)
        assert isinstance(jobs_data, dict)
        for job in jobs_data.get("jobs", []):
            if job.get("conclusion") == "failure":
                log(f"[!] Job thất bại: {job.get('name')}")
                for step in job.get("steps", []):
                    if step.get("conclusion") == "failure":
                        log(f"    -> Bước lỗi: {step.get('name')}")
                raw_log = download_binary_Following_noauth_redirect(
                    f"{API_BASE}/repos/{owner}/{repo_name}/actions/jobs/{job['id']}/logs",
                    token,
                )
                tail_lines = raw_log.decode("utf-8", errors="replace").splitlines()[-45:]
                log("--- Chi tiết 45 dòng cuối của Xcode build log ---")
                for ln in tail_lines:
                    log("  " + ln)
    except Exception as exc:
        log(f"[!] Không đọc được chi tiết job log: {exc}")


def wait_for_ipa_artifact(owner: str, repo_name: str, head_sha: str, branch: str, token: str) -> None:
    log("[*] Đang kích hoạt máy chủ macOS-15 (Xcode 16) trên GitHub Actions...")
    run_id = None
    run_html_url = f"https://github.com/{owner}/{repo_name}/actions"

    for attempt in range(24):
        time.sleep(3.5)
        _, runs_resp, _ = gh_request("GET", f"/repos/{owner}/{repo_name}/actions/runs?per_page=10", token)
        assert isinstance(runs_resp, dict)
        for r in runs_resp.get("workflow_runs", []):
            if r.get("head_sha") == head_sha:
                run_id = r["id"]
                run_html_url = r["html_url"]
                break
        if run_id is not None:
            break

        # Explicitly dispatch workflow if push event didn't start a run yet
        if attempt % 2 == 1:
            try:
                gh_request(
                    "POST",
                    f"/repos/{owner}/{repo_name}/actions/workflows/ios-build.yml/dispatches",
                    token,
                    payload={"ref": branch},
                )
            except RuntimeError:
                pass

    if run_id is None:
        raise RuntimeError(f"Không tìm thấy tiến trình GitHub Actions. Hãy kiểm tra tại: {run_html_url}")

    log(f"[*] Theo dõi trực tiếp tiến trình biên dịch tại: {run_html_url}")
    start_ts = time.time()
    while True:
        _, run_data, _ = gh_request("GET", f"/repos/{owner}/{repo_name}/actions/runs/{run_id}", token)
        assert isinstance(run_data, dict)
        status = run_data.get("status")
        conclusion = run_data.get("conclusion")
        elapsed = int(time.time() - start_ts)
        log(f"    [{elapsed:3d}s] Trạng thái macOS Xcode build: {status}" + (f" ({conclusion})" if conclusion else ""))

        if status == "completed":
            if conclusion != "success":
                dump_failed_job_logs(owner, repo_name, run_id, token)
                raise RuntimeError(f"Quá trình biên dịch thất bại ({conclusion}). Xem log tại: {run_html_url}")
            break
        time.sleep(10)

    log("[*] Biên dịch hoàn tất! Đang tải gói NVTSnapMedia.ipa về máy...")
    _, artifacts_data, _ = gh_request("GET", f"/repos/{owner}/{repo_name}/actions/runs/{run_id}/artifacts", token)
    assert isinstance(artifacts_data, dict)
    artifacts = artifacts_data.get("artifacts", [])
    target_artifact = next(
        (a for a in artifacts if "IPA" in a.get("name", "") or "NVTSnapMedia" in a.get("name", "")),
        None,
    )
    if not target_artifact:
        raise RuntimeError("Không tìm thấy Artifact chứa tệp .ipa trong kết quả build.")

    zip_bytes = download_binary_Following_noauth_redirect(target_artifact["archive_download_url"], token)
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        ipa_names = [n for n in zf.namelist() if n.lower().endswith(".ipa")]
        if not ipa_names:
            raise RuntimeError("Tệp nén Artifact không chứa file .ipa.")
        OUTPUT_IPA.write_bytes(zf.read(ipa_names[0]))

    size_mb = OUTPUT_IPA.stat().st_size / (1024 * 1024)
    log("\n============================================================")
    log(f"[HOÀN TẤT] Đã đóng gói thành công: {OUTPUT_IPA} ({size_mb:.2f} MB)")
    log("============================================================")


def prompt_token_gui_or_cli() -> str:
    try:
        import tkinter as tk
        import webbrowser

        result = {"token": ""}
        root = tk.Tk()
        root.title("NVTSnapMedia — Đóng gói NVTSnapMedia.ipa cho iOS")
        root.geometry("560x250")
        root.resizable(False, False)

        lbl_title = tk.Label(
            root,
            text="Đóng gói tự động NVTSnapMedia.ipa qua máy chủ macOS (GitHub Actions)",
            font=("Segoe UI", 10, "bold"),
        )
        lbl_title.pack(pady=(16, 6))

        lbl_sub = tk.Label(
            root,
            text="Bước 1: Nhấn nút bên dưới để tạo GitHub Token (tích chọn 'repo' và 'workflow').\nBước 2: Dán (Ctrl+V) mã Token ghp_... vào ô dưới đây và nhấn Bắt đầu.",
            justify="left",
        )
        lbl_sub.pack(pady=(0, 8))

        btn_open = tk.Button(
            root,
            text="1. Mở trang tạo GitHub Token (repo + workflow)",
            command=lambda: webbrowser.open("https://github.com/settings/tokens/new?scopes=repo,workflow&description=NVTSnapMedia-IPA-Builder"),
        )
        btn_open.pack(pady=(0, 10))

        entry = tk.Entry(root, width=62)
        entry.pack(pady=4)
        entry.focus_set()

        def on_submit():
            result["token"] = entry.get().strip()
            root.destroy()

        btn_go = tk.Button(
            root,
            text="2. Bắt đầu biên dịch & tải NVTSnapMedia.ipa",
            bg="#4F46E5",
            fg="white",
            font=("Segoe UI", 10, "bold"),
            padx=14,
            pady=6,
            command=on_submit,
        )
        btn_go.pack(pady=12)
        root.bind("<Return>", lambda _e: on_submit())
        root.mainloop()
        return result["token"]
    except Exception:
        print("Tạo GitHub Personal Access Token (quyền repo + workflow) tại:")
        print("  https://github.com/settings/tokens/new?scopes=repo,workflow")
        return input("Dán GitHub Token (ghp_...) vào đây rồi nhấn Enter: ").strip()


def main() -> None:
    parser = argparse.ArgumentParser(description="Build NVTSnapMedia.ipa via GitHub macOS runner")
    parser.add_argument("--token", default="", help="GitHub Personal Access Token (repo + workflow)")
    parser.add_argument("--repo", default="", help="Repository name (default: NVTSnapMedia-iOS-Build)")
    args = parser.parse_args()

    try:
        LOG_FILE.write_text("", encoding="utf-8")
    except OSError:
        pass

    log("=== NVTSnapMedia — Đóng gói tự động NVTSnapMedia.ipa cho iOS ===")
    token = (args.token or os.environ.get("GITHUB_TOKEN", "")).strip()
    if not token:
        token = prompt_token_gui_or_cli()

    if not token:
        log("[!] Chưa cung cấp GitHub Token. Dừng đóng gói.")
        sys.exit(1)

    try:
        _, user_info, _ = gh_request("GET", "/user", token)
        assert isinstance(user_info, dict)
        owner = user_info["login"]
        repo_name = (args.repo or os.environ.get("GITHUB_REPO", "") or DEFAULT_REPO_NAME).strip()
        log(f"[*] Đã xác thực tài khoản GitHub: @{owner}")

        branch = ensure_repo(owner, repo_name, token)
        files = collect_project_files()
        commit_sha = push_tree_commit(owner, repo_name, branch, token, files)
        wait_for_ipa_artifact(owner, repo_name, commit_sha, branch, token)
    except Exception as exc:
        log(f"\n[LỖI] {exc}")
        sys.exit(1)


if __name__ == "__main__":
    main()
