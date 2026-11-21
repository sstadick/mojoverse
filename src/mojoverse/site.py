"""Shared presentation for individual package docs and the combined site."""

from pathlib import Path
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

import yaml

from .versions import SITE_URL, VERSIONS


def navigation(directory, root):
    """Keep module overviews above symbols and use identifiers as link labels."""
    entries = []
    for name, label in (("index.md", "Guide & examples"), ("_index.md", "Overview")):
        if (directory / name).is_file():
            entries.append({label: (directory / name).relative_to(root).as_posix()})
    for path in sorted(directory.iterdir()):
        if path.is_dir():
            children = navigation(path, root)
            if children:
                entries.append({path.name: children})
        elif path.suffix == ".md" and path.name not in ("index.md", "_index.md"):
            entries.append({path.stem: path.relative_to(root).as_posix()})
    return entries


def build_site(source, output, title, nav=None, *, catalog=False, version=None):
    shutil.copytree(Path(__file__).with_name("assets"), source / "assets", dirs_exist_ok=True)
    config = {
        "site_name": title,
        "docs_dir": source.relative_to(output.parent).as_posix(),
        "site_dir": output.name,
        "use_directory_urls": False,
        "repo_url": "https://github.com/sstadick/mojoverse",
        "edit_uri": "",
        "theme": {
            "variant": "classic",
            "font": False,
            "custom_dir": str(Path(__file__).with_name("theme")),
            "features": ["navigation.indexes", "navigation.top", "toc.follow", "search.highlight", "content.code.copy"],
            "palette": [
                {"scheme": "default", "media": "(prefers-color-scheme: light)", "toggle": {"icon": "material/weather-night", "name": "Switch to dark mode"}},
                {"scheme": "slate", "media": "(prefers-color-scheme: dark)", "toggle": {"icon": "material/weather-sunny", "name": "Switch to light mode"}},
            ],
        },
        "extra": {"library_catalog": catalog},
        "nav": nav if nav is not None else navigation(source, source),
        "markdown_extensions": [
            "attr_list",
            {"pymdownx.highlight": {"pygments_lang_class": True, "extend_pygments_lang": [{"name": "mojo", "lang": "mojo-current"}]}},
            "pymdownx.superfences",
            {"toc": {"permalink": True}},
        ],
        "extra_css": ["assets/docs.css"],
        "extra_javascript": ["assets/docs.js"],
    }
    if version is not None:
        if version not in {item["version"] for item in VERSIONS}:
            raise ValueError(f"Unknown documentation version: {version}")
        config["site_url"] = f"{SITE_URL}{version}/"
        config["extra"]["version"] = {"provider": "mike", "default": "nightly"}
    config_path = output.parent / "mkdocs.yml"
    config_path.write_text(yaml.safe_dump(config, sort_keys=False))
    subprocess.run([sys.executable, "-m", "zensical", "build", "--strict", "--config-file", str(config_path)], cwd=output.parent, check=True)
    if version is not None:
        # The version selector requires the version root in the sitemap to retain
        # the current page. File-style URLs otherwise list only index.html.
        namespace = "http://www.sitemaps.org/schemas/sitemap/0.9"
        ET.register_namespace("", namespace)
        sitemap = ET.parse(output / "sitemap.xml")
        entry = ET.SubElement(sitemap.getroot(), f"{{{namespace}}}url")
        ET.SubElement(entry, f"{{{namespace}}}loc").text = config["site_url"]
        sitemap.write(output / "sitemap.xml", encoding="utf-8", xml_declaration=True)
    # GitHub Pages supplies the error page; standalone root-relative 404 links
    # don't work when these sites are served from a package subdirectory.
    (output / "404.html").unlink(missing_ok=True)
