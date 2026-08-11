#!/usr/bin/env python3
"""ドキュメント整合性チェック。

コード（site.yml / Makefile / deploy.yml / テンプレート）とドキュメントの
機械的に検証できる整合性を突き合わせる。CI（docs_check.yml）とローカル
（uv run python scripts/check_docs.py）の両方から実行される。

チェック項目:
  C1: ansible/roles/ のディレクトリ集合 = site.yml の tags 集合
  C2: 各ロールに Makefile の <role> / deploy-<role> ターゲットと .PHONY 登録がある
  C3: deploy.yml のロール列挙 5 箇所が「全ロール − {test, setup}」と一致する
  C4: 全ロールに README.md が存在する
  C5: ansible/README.md に全ロール名が出現する
  C6: ルート README.md に Makefile の全ターゲットが `make <target>` 形式で出現する
  C7: tofu/README.md に tofu/Makefile の全ターゲットが出現する
  C8: Git 管理下の全 Markdown の相対リンク先ファイルが実在する
  C9: observability_alert_containers の各要素が compose テンプレートの container_name に実在する
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# CD 対象外ロール（deploy.yml の設計: setup は --ask-become-pass が必要、test はテスト用）
CD_EXCLUDED_ROLES = {"test", "setup"}


def roles_dirs() -> set[str]:
    return {p.name for p in (ROOT / "ansible" / "roles").iterdir() if p.is_dir()}


def make_targets(makefile: Path) -> tuple[set[str], set[str]]:
    """(ターゲット集合, .PHONY 集合) を返す。"""
    targets: set[str] = set()
    phony: set[str] = set()
    for line in makefile.read_text().splitlines():
        if line.startswith(".PHONY:"):
            phony |= set(line.removeprefix(".PHONY:").split())
        elif m := re.match(r"^([A-Za-z0-9][A-Za-z0-9_-]*):", line):
            targets.add(m.group(1))
    return targets, phony


def check_c1_site_tags() -> list[str]:
    site = ROOT / "ansible" / "site.yml"
    tags = set(re.findall(r"^\s*tags:\s*([A-Za-z0-9_-]+)\s*$", site.read_text(), re.M))
    roles = roles_dirs()
    errors = []
    for role in sorted(roles - tags):
        errors.append(f"[C1] {site}: ロール {role} のタグが無い / 期待: tags: {role} のプレイ / 実際: 未定義")
    for tag in sorted(tags - roles):
        errors.append(f"[C1] {site}: タグ {tag} に対応するロールディレクトリが無い")
    return errors


def check_c2_make_targets() -> list[str]:
    makefile = ROOT / "Makefile"
    targets, phony = make_targets(makefile)
    errors = []
    for role in sorted(roles_dirs()):
        for target in (role, f"deploy-{role}"):
            if target not in targets:
                errors.append(f"[C2] {makefile}: ターゲット {target} が無い / 期待: ロール {role} の実行手段")
            elif target not in phony:
                errors.append(f"[C2] {makefile}: {target} が .PHONY に未登録")
    return errors


def check_c3_deploy_roles() -> list[str]:
    deploy = ROOT / ".github" / "workflows" / "deploy.yml"
    text = deploy.read_text()
    expected = roles_dirs() - CD_EXCLUDED_ROLES
    errors = []

    # 列挙 5 箇所を抽出する。抽出数が想定と異なる場合は deploy.yml の構造変更なので明示的に落とす
    spots: list[tuple[str, str]] = []
    if m := re.search(r"default:\s*'([a-z0-9,_-]+)'", text):
        spots.append(("workflow_dispatch の default", m.group(1)))
    if m := re.search(r'ALLOWED_ROLES="([^"]+)"', text):
        spots.append(("ALLOWED_ROLES", m.group(1)))
    literal_echoes = re.findall(r'"roles=([a-z][a-z0-9,_-]*)"', text)
    for value in literal_echoes:
        spots.append(("roles= のリテラル echo", value))
    if m := re.search(r"for role in ([a-z0-9 _-]+); do", text):
        spots.append(("for ループ", m.group(1)))

    expected_spot_count = 5  # default / ALLOWED_ROLES / echo ×2 / for ループ
    if len(spots) != expected_spot_count:
        errors.append(
            f"[C3] {deploy}: ロール列挙の検出数が想定と異なる / 期待: {expected_spot_count} 箇所 / "
            f"実際: {len(spots)} 箇所（構造が変わった場合は scripts/check_docs.py も更新すること）"
        )

    for label, value in spots:
        found = set(re.split(r"[,\s]+", value.strip()))
        if found != expected:
            errors.append(
                f"[C3] {deploy}: {label} がロール構成と不一致 / "
                f"期待: {' '.join(sorted(expected))} / 実際: {' '.join(sorted(found))}"
            )
    return errors


def check_c4_role_readmes() -> list[str]:
    errors = []
    for role in sorted(roles_dirs()):
        readme = ROOT / "ansible" / "roles" / role / "README.md"
        if not readme.is_file():
            errors.append(f"[C4] {readme}: ロール README が無い / 期待: 全ロールに README.md")
    return errors


def check_c5_ansible_readme() -> list[str]:
    readme = ROOT / "ansible" / "README.md"
    text = readme.read_text()
    errors = []
    for role in sorted(roles_dirs()):
        if not re.search(rf"\b{re.escape(role)}\b", text):
            errors.append(f"[C5] {readme}: ロール {role} への言及が無い / 期待: ロール一覧に記載")
    return errors


def _check_targets_in_readme(makefile: Path, readme: Path, check_id: str) -> list[str]:
    targets, _ = make_targets(makefile)
    text = readme.read_text()
    errors = []
    for target in sorted(targets):
        if not re.search(rf"make {re.escape(target)}(?![A-Za-z0-9_-])", text):
            errors.append(f"[{check_id}] {readme}: `make {target}` の記載が無い / 期待: {makefile} の全ターゲットを記載")
    return errors


def check_c6_root_readme_targets() -> list[str]:
    return _check_targets_in_readme(ROOT / "Makefile", ROOT / "README.md", "C6")


def check_c7_tofu_readme_targets() -> list[str]:
    return _check_targets_in_readme(ROOT / "tofu" / "Makefile", ROOT / "tofu" / "README.md", "C7")


def check_c8_markdown_links() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "*.md"], cwd=ROOT, capture_output=True, text=True, check=True
    )
    errors = []
    for rel in result.stdout.splitlines():
        md = ROOT / rel
        if not md.is_file():  # 追跡中だがローカルに無いファイルの欠落検出は C4 の責務
            continue
        for m in re.finditer(r"\[[^\]]*\]\(([^)]+)\)", md.read_text()):
            target = m.group(1).split("#", 1)[0].strip()
            if not target or target.startswith(("http://", "https://", "mailto:")):
                continue
            if not (md.parent / target).resolve().exists():
                errors.append(f"[C8] {rel}: リンク先が実在しない / 実際: {target}")
    return errors


def check_c9_alert_containers() -> list[str]:
    defaults = ROOT / "ansible" / "roles" / "observability" / "defaults" / "main.yml"
    m = re.search(
        r"^observability_alert_containers:\n((?:\s+-\s+\S+\n)+)", defaults.read_text(), re.M
    )
    if not m:
        return [f"[C9] {defaults}: observability_alert_containers を検出できない（形式が変わった場合はスクリプトを更新）"]
    alert_containers = re.findall(r"-\s+(\S+)", m.group(1))

    container_names: set[str] = set()
    for template in (ROOT / "ansible" / "roles").glob("*/templates/docker-compose.yml.j2"):
        container_names |= set(re.findall(r"container_name:\s*([A-Za-z0-9._-]+)", template.read_text()))

    errors = []
    for name in alert_containers:
        if name not in container_names:
            errors.append(
                f"[C9] {defaults}: 監視対象 {name} がどの compose テンプレートの container_name にも無い / "
                f"期待: 実在するコンテナ名のみを列挙"
            )
    return errors


CHECKS = [
    check_c1_site_tags,
    check_c2_make_targets,
    check_c3_deploy_roles,
    check_c4_role_readmes,
    check_c5_ansible_readme,
    check_c6_root_readme_targets,
    check_c7_tofu_readme_targets,
    check_c8_markdown_links,
    check_c9_alert_containers,
]


def main() -> int:
    all_errors: list[str] = []
    for check in CHECKS:
        all_errors.extend(check())
    if all_errors:
        print(f"ドキュメント整合性チェック: {len(all_errors)} 件の不整合", file=sys.stderr)
        for error in all_errors:
            print(f"  {error}", file=sys.stderr)
        return 1
    print(f"ドキュメント整合性チェック: {len(CHECKS)} 項目すべて OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
